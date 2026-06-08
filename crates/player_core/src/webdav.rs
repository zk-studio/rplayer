use anyhow::Result;
use reqwest::{Client, Method};
use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct WebdavConfig {
    pub base_url: String,
    pub username: Option<String>,
    pub password: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct RemoteEntry {
    pub href: String,
    pub name: String,
    pub is_dir: bool,
    pub content_length: Option<u64>,
}

#[derive(Clone)]
pub struct WebdavClient {
    http: Client,
    config: WebdavConfig,
}

impl WebdavClient {
    pub fn new(config: WebdavConfig) -> Self {
        Self {
            http: Client::new(),
            config,
        }
    }

    pub async fn test_connection(&self) -> Result<()> {
        let method = Method::from_bytes(b"PROPFIND")?;
        let request = self
            .http
            .request(method, &self.config.base_url)
            .header("Depth", "0");

        self.with_auth(request).send().await?.error_for_status()?;
        Ok(())
    }

    fn with_auth(&self, request: reqwest::RequestBuilder) -> reqwest::RequestBuilder {
        match (&self.config.username, &self.config.password) {
            (Some(username), Some(password)) => request.basic_auth(username, Some(password)),
            _ => request,
        }
    }
}

