use anyhow::Result;
use percent_encoding::percent_decode_str;
use reqwest::{Client, Method};
use serde::{Deserialize, Serialize};
use url::Url;

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

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct WebdavDirectoryEntry {
    pub name: String,
    pub path: String,
    pub url: String,
    pub is_dir: bool,
    pub size: Option<u64>,
}

#[derive(Clone)]
pub struct WebdavClient {
    http: Client,
    config: WebdavConfig,
}

pub fn parse_webdav_entries_json(
    body: &str,
    base_url: &str,
    request_url: &str,
    current_path: &str,
) -> Result<String> {
    serde_json::to_string(&parse_webdav_entries(
        body,
        base_url,
        request_url,
        current_path,
    )?)
    .map_err(anyhow::Error::from)
}

pub fn parse_webdav_entries(
    body: &str,
    base_url: &str,
    request_url: &str,
    current_path: &str,
) -> Result<Vec<WebdavDirectoryEntry>> {
    let document = roxmltree::Document::parse(body)?;
    let base_url = ensure_trailing_slash(base_url);
    let base_uri = Url::parse(&base_url)?;
    let request_uri = Url::parse(request_url)?;
    let mut base_path = decode_path(base_uri.path());
    if !base_path.ends_with('/') {
        base_path.push('/');
    }
    let current = normalize_remote_dir(current_path);
    let request_path = decode_path(request_uri.path());

    let mut entries = Vec::new();
    for response in document
        .descendants()
        .filter(|node| node.is_element() && node.tag_name().name() == "response")
    {
        let Some(href) = first_descendant_text(response, "href") else {
            continue;
        };
        if href.is_empty() {
            continue;
        }

        let resolved = request_uri.join(&href)?;
        let decoded_path = decode_path(resolved.path());
        let mut remote_path = if decoded_path.starts_with(&base_path) {
            format!("/{}", &decoded_path[base_path.len()..])
        } else {
            decoded_path.clone()
        };
        if remote_path.is_empty() {
            remote_path = "/".to_string();
        }

        let is_dir = response
            .descendants()
            .any(|node| node.is_element() && node.tag_name().name() == "collection");
        if is_dir {
            remote_path = normalize_remote_dir(&remote_path);
        }
        if remote_path == "/" || remote_path == current || decoded_path == request_path {
            continue;
        }

        let display_name = first_descendant_text(response, "displayname");
        let size = first_descendant_text(response, "getcontentlength")
            .and_then(|value| value.parse::<u64>().ok());
        let name = display_name
            .filter(|value| !value.is_empty())
            .unwrap_or_else(|| last_path_part(&remote_path));

        entries.push(WebdavDirectoryEntry {
            name,
            path: remote_path,
            url: resolved.to_string(),
            is_dir,
            size,
        });
    }

    entries.sort_by(|a, b| {
        b.is_dir
            .cmp(&a.is_dir)
            .then_with(|| a.name.to_lowercase().cmp(&b.name.to_lowercase()))
    });
    Ok(entries)
}

fn first_descendant_text(node: roxmltree::Node<'_, '_>, local_name: &str) -> Option<String> {
    node.descendants()
        .find(|child| child.is_element() && child.tag_name().name() == local_name)
        .and_then(|child| child.text())
        .map(|value| value.trim().to_string())
}

fn normalize_remote_dir(value: &str) -> String {
    let mut path = value.trim().to_string();
    if path.is_empty() {
        return "/".to_string();
    }
    if !path.starts_with('/') {
        path.insert(0, '/');
    }
    if !path.ends_with('/') {
        path.push('/');
    }
    path
}

fn ensure_trailing_slash(value: &str) -> String {
    if value.ends_with('/') {
        value.to_string()
    } else {
        format!("{value}/")
    }
}

fn decode_path(value: &str) -> String {
    percent_decode_str(value).decode_utf8_lossy().to_string()
}

fn last_path_part(value: &str) -> String {
    value
        .trim_end_matches('/')
        .rsplit('/')
        .find(|part| !part.is_empty())
        .unwrap_or(value)
        .to_string()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parses_propfind_entries() {
        let body = r#"<?xml version="1.0" encoding="utf-8" ?>
<d:multistatus xmlns:d="DAV:">
  <d:response>
    <d:href>/dav/Movies/</d:href>
    <d:propstat><d:prop><d:resourcetype><d:collection/></d:resourcetype></d:prop></d:propstat>
  </d:response>
  <d:response>
    <d:href>/dav/Movies/Show/</d:href>
    <d:propstat><d:prop><d:displayname>Show</d:displayname><d:resourcetype><d:collection/></d:resourcetype></d:prop></d:propstat>
  </d:response>
  <d:response>
    <d:href>/dav/Movies/Movie%20A.mkv</d:href>
    <d:propstat><d:prop><d:displayname>Movie A.mkv</d:displayname><d:getcontentlength>42</d:getcontentlength></d:prop></d:propstat>
  </d:response>
</d:multistatus>"#;

        let entries = parse_webdav_entries(
            body,
            "https://example.com/dav/",
            "https://example.com/dav/Movies/",
            "/Movies/",
        )
        .unwrap();

        assert_eq!(entries.len(), 2);
        assert_eq!(entries[0].path, "/Movies/Show/");
        assert!(entries[0].is_dir);
        assert_eq!(entries[1].path, "/Movies/Movie A.mkv");
        assert_eq!(entries[1].size, Some(42));
    }

    #[test]
    fn resolves_relative_href() {
        let body = r#"<d:multistatus xmlns:d="DAV:">
  <d:response>
    <d:href>Episode%2001.mp4</d:href>
    <d:propstat><d:prop><d:getcontentlength>7</d:getcontentlength></d:prop></d:propstat>
  </d:response>
</d:multistatus>"#;

        let entries = parse_webdav_entries(
            body,
            "https://example.com/dav/",
            "https://example.com/dav/Shows/",
            "/Shows/",
        )
        .unwrap();

        assert_eq!(entries[0].name, "Episode 01.mp4");
        assert_eq!(entries[0].path, "/Shows/Episode 01.mp4");
    }
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
