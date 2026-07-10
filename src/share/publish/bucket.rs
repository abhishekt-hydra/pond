//! [`BucketPublisher`]: writes a [`ShareArtifact`](super::super::ShareArtifact)
//! to a bucket via `object_store`, mirroring the config -> bucket client
//! construction already used by `substrate::export_write` /
//! `substrate::storage_check`. The bucket is not assumed public: unless
//! `public_base_url` is configured, the printed URL is a presigned GET link
//! (see [`presigned_url`]), not the bucket's raw address.

use std::{collections::BTreeMap, sync::Arc, time::Duration};

use anyhow::{Context, Result};
use http::Method;
use lance_io::object_store::{
    ObjectStore, ObjectStoreParams, ObjectStoreRegistry, StorageOptionsAccessor,
};
use object_store::{
    Attribute, ObjectStoreExt, PutMode, PutOptions, PutPayload,
    aws::{AmazonS3Builder, AmazonS3ConfigKey},
    azure::{AzureConfigKey, MicrosoftAzureBuilder},
    gcp::{GoogleCloudStorageBuilder, GoogleConfigKey},
    path::Path as ObjectPath,
    signer::Signer,
};
use url::Url;

use crate::{
    config::CredsSet,
    share::{ShareArtifact, SharePublisher},
    substrate::StorageUrl,
};

pub struct BucketPublisher {
    bucket_url: StorageUrl,
    creds: BTreeMap<String, CredsSet>,
    /// Public origin serving `bucket_url`'s contents, for a genuinely public
    /// bucket / CDN. `None` (the default) means the bucket is private: the
    /// published URL is presigned instead (see `presign_expiry`).
    public_base_url: Option<String>,
    /// Lifetime of the presigned URL returned when `public_base_url` is
    /// unset. Ignored otherwise.
    presign_expiry: Duration,
}

impl BucketPublisher {
    pub fn new(
        bucket: &str,
        creds: BTreeMap<String, CredsSet>,
        public_base_url: Option<String>,
        presign_expiry: Duration,
    ) -> Result<Self> {
        let bucket_url = StorageUrl::parse(bucket)
            .with_context(|| format!("invalid share bucket URL {bucket:?}"))?;
        Ok(Self {
            bucket_url,
            creds,
            public_base_url,
            presign_expiry,
        })
    }
}

#[async_trait::async_trait]
impl SharePublisher for BucketPublisher {
    async fn publish(&self, id: &str, artifact: &ShareArtifact) -> Result<String> {
        let resolved = self.bucket_url.resolve(&self.creds)?;
        let params = ObjectStoreParams {
            storage_options_accessor: (!resolved.options.is_empty()).then(|| {
                Arc::new(StorageOptionsAccessor::with_static_options(
                    resolved.options.clone(),
                ))
            }),
            ..Default::default()
        };
        let object_uri = format!(
            "{}/{}.{}",
            resolved.lance_url().as_str().trim_end_matches('/'),
            id,
            artifact.ext,
        );
        let registry = Arc::new(ObjectStoreRegistry::default());
        let (store, path) = ObjectStore::from_uri_and_params(registry, &object_uri, &params)
            .await
            .with_context(|| format!("failed to open share bucket for {object_uri}"))?;

        // A browser must render this, not download it - explicit Content-Type
        // is required, unlike every other object_store write in pond (Lance's
        // own format doesn't care, and JSONL exports are meant to be
        // downloaded). See docs/overview/share-feature.md.
        let opts = PutOptions {
            attributes: [(Attribute::ContentType, artifact.content_type.clone())]
                .into_iter()
                .collect(),
            mode: PutMode::Overwrite,
            ..Default::default()
        };
        let put = store
            .inner
            .put_opts(&path, PutPayload::from(artifact.bytes.clone()), opts)
            .await;
        match put {
            Ok(_) => {}
            // `LocalFileSystem` rejects any `put_opts` with attributes set at
            // all (no Content-Type concept for a local file) - every real S3-
            // compatible backend (R2, S3, Hetzner, MinIO, B2) supports it, so
            // this only matters for a local `--to file://` smoke test. Retry
            // once without attributes rather than failing a publish that
            // would otherwise fully succeed.
            Err(object_store::Error::NotImplemented { .. }) => {
                store
                    .inner
                    .put(&path, PutPayload::from(artifact.bytes.clone()))
                    .await
                    .with_context(|| format!("failed to publish share artifact to {object_uri}"))?;
            }
            Err(error) => {
                return Err(anyhow::anyhow!(error))
                    .with_context(|| format!("failed to publish share artifact to {object_uri}"));
            }
        }

        if let Some(base) = &self.public_base_url {
            return Ok(format!(
                "{}/{}.{}",
                base.trim_end_matches('/'),
                id,
                artifact.ext
            ));
        }
        presigned_url(
            resolved.lance_url(),
            &resolved.options,
            &path,
            self.presign_expiry,
            &object_uri,
        )
        .await
        .with_context(|| format!("failed to presign share URL for {object_uri}"))
    }
}

/// Sign a time-limited GET URL for `path` inside the bucket `lance_url`
/// (`options` are the same creds-resolved `object_store` config the write
/// above used) so a private bucket never needs to be made public just to
/// share one object. Schemes without a `Signer` impl, namely `file://` and
/// `memory://` (the local smoke-test targets), fall back to `object_uri`
/// verbatim, the same value pond printed before presigning existed. It can't
/// be reconstructed from `lance_url` + `path`: `path` is already relative to
/// the *bucket root* and so re-includes any prefix `lance_url` itself
/// carries (e.g. `[share].bucket = ".../my-bucket/shares"` widens to `path =
/// "shares/share_xyz.html"`), which would double it up.
async fn presigned_url(
    lance_url: &Url,
    options: &std::collections::HashMap<String, String>,
    path: &ObjectPath,
    expiry: Duration,
    object_uri: &str,
) -> Result<String> {
    match lance_url.scheme() {
        "s3" => {
            let mut builder = AmazonS3Builder::new().with_url(lance_url.as_str());
            for (key, value) in options {
                if let Ok(key) = key.parse::<AmazonS3ConfigKey>() {
                    builder = builder.with_config(key, value.clone());
                }
            }
            let store = builder
                .build()
                .context("failed to build S3 client for presigning")?;
            Ok(store
                .signed_url(Method::GET, path, expiry)
                .await?
                .to_string())
        }
        "gs" => {
            let mut builder = GoogleCloudStorageBuilder::new().with_url(lance_url.as_str());
            for (key, value) in options {
                if let Ok(key) = key.parse::<GoogleConfigKey>() {
                    builder = builder.with_config(key, value.clone());
                }
            }
            let store = builder
                .build()
                .context("failed to build GCS client for presigning")?;
            Ok(store
                .signed_url(Method::GET, path, expiry)
                .await?
                .to_string())
        }
        "az" => {
            let mut builder = MicrosoftAzureBuilder::new().with_url(lance_url.as_str());
            for (key, value) in options {
                if let Ok(key) = key.parse::<AzureConfigKey>() {
                    builder = builder.with_config(key, value.clone());
                }
            }
            let store = builder
                .build()
                .context("failed to build Azure client for presigning")?;
            Ok(store
                .signed_url(Method::GET, path, expiry)
                .await?
                .to_string())
        }
        // `file://` / `memory://`: no `Signer` impl, and nothing to protect -
        // these only ever come from a local `--to` smoke-test target.
        _ => Ok(object_uri.to_owned()),
    }
}
