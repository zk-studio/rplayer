use anyhow::Result;
use reqwest::Client;
use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct DanmuMatchRequest {
    pub title: String,
    pub season: Option<u16>,
    pub episode: Option<u16>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct DanmuEvent {
    pub time_ms: u64,
    pub mode: DanmuMode,
    pub color: u32,
    pub text: String,
    pub source: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum DanmuMode {
    Scroll,
    Top,
    Bottom,
    Unknown,
}

#[derive(Clone)]
pub struct DanmuClient {
    http: Client,
    base_url: String,
    token: Option<String>,
}

impl DanmuClient {
    pub fn new(base_url: impl Into<String>, token: Option<String>) -> Self {
        Self {
            http: Client::new(),
            base_url: base_url.into().trim_end_matches('/').to_string(),
            token,
        }
    }

    pub async fn match_media(&self, request: &DanmuMatchRequest) -> Result<serde_json::Value> {
        let url = self.url("/api/v2/match");
        let response = self
            .http
            .post(url)
            .json(request)
            .send()
            .await?
            .error_for_status()?
            .json()
            .await?;
        Ok(response)
    }

    pub async fn get_comment_json(&self, comment_id: &str) -> Result<serde_json::Value> {
        let url = self.url(&format!("/api/v2/comment/{comment_id}"));
        let response = self
            .http
            .get(url)
            .query(&[("format", "json")])
            .send()
            .await?
            .error_for_status()?
            .json()
            .await?;
        Ok(response)
    }

    pub async fn get_comment_by_url(&self, video_url: &str) -> Result<serde_json::Value> {
        let url = self.url("/api/v2/comment");
        let response = self
            .http
            .get(url)
            .query(&[("url", video_url), ("format", "json")])
            .send()
            .await?
            .error_for_status()?
            .json()
            .await?;
        Ok(response)
    }

    fn url(&self, path: &str) -> String {
        match &self.token {
            Some(token) if !token.is_empty() => format!("{}/{token}{path}", self.base_url),
            _ => format!("{}{}", self.base_url, path),
        }
    }
}
