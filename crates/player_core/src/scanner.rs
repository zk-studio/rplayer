use std::collections::VecDeque;
use std::fs;
use std::path::Path;

use anyhow::{Context, Result};
use serde::{Deserialize, Serialize};

const VIDEO_EXTENSIONS: &[&str] = &[
    "mp4", "mkv", "mov", "avi", "flv", "wmv", "webm", "m4v", "ts", "m2ts", "mts", "mpg", "mpeg",
    "3gp", "rm", "rmvb", "vob", "ogv", "asf",
];

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct ScannedVideo {
    pub path: String,
    pub file_name: String,
    pub parent_name: String,
    pub size: Option<u64>,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct LocalDirectoryEntry {
    pub name: String,
    pub path: String,
    pub is_dir: bool,
    pub size: Option<u64>,
}

pub fn scan_local_videos(root: impl AsRef<Path>) -> Result<Vec<ScannedVideo>> {
    let root = root.as_ref();
    let metadata =
        fs::metadata(root).with_context(|| format!("failed to read {}", root.display()))?;
    if !metadata.is_dir() {
        anyhow::bail!("{} is not a directory", root.display());
    }

    let mut videos = Vec::new();
    let mut queue = VecDeque::from([root.to_path_buf()]);

    while let Some(dir) = queue.pop_front() {
        let entries = match fs::read_dir(&dir) {
            Ok(entries) => entries,
            Err(_) => continue,
        };

        for entry in entries.flatten() {
            let path = entry.path();
            let file_type = match entry.file_type() {
                Ok(file_type) => file_type,
                Err(_) => continue,
            };

            if file_type.is_dir() {
                queue.push_back(path);
            } else if file_type.is_file() && is_video_path(&path) {
                let size = entry.metadata().ok().map(|value| value.len());
                videos.push(ScannedVideo {
                    file_name: path
                        .file_name()
                        .and_then(|value| value.to_str())
                        .unwrap_or_default()
                        .to_string(),
                    parent_name: path
                        .parent()
                        .and_then(Path::file_name)
                        .and_then(|value| value.to_str())
                        .unwrap_or_default()
                        .to_string(),
                    path: path.to_string_lossy().to_string(),
                    size,
                });
            }
        }
    }

    videos.sort_by(|a, b| a.path.to_lowercase().cmp(&b.path.to_lowercase()));
    Ok(videos)
}

pub fn scan_local_videos_json(root: &str) -> Result<String> {
    serde_json::to_string(&scan_local_videos(root)?).context("failed to encode scan result")
}

pub fn list_local_directory(root: impl AsRef<Path>) -> Result<Vec<LocalDirectoryEntry>> {
    let root = root.as_ref();
    let metadata =
        fs::metadata(root).with_context(|| format!("failed to read {}", root.display()))?;
    if !metadata.is_dir() {
        anyhow::bail!("{} is not a directory", root.display());
    }

    let mut entries = Vec::new();
    for entry in fs::read_dir(root)
        .with_context(|| format!("failed to list {}", root.display()))?
        .flatten()
    {
        let path = entry.path();
        let file_type = match entry.file_type() {
            Ok(file_type) => file_type,
            Err(_) => continue,
        };
        let is_dir = file_type.is_dir();
        let is_file = file_type.is_file();
        if !is_dir && (!is_file || !is_video_path(&path)) {
            continue;
        }

        entries.push(LocalDirectoryEntry {
            name: path
                .file_name()
                .and_then(|value| value.to_str())
                .unwrap_or_default()
                .to_string(),
            path: path.to_string_lossy().to_string(),
            is_dir,
            size: is_file
                .then(|| entry.metadata().ok().map(|value| value.len()))
                .flatten(),
        });
    }

    entries.sort_by(|a, b| {
        b.is_dir
            .cmp(&a.is_dir)
            .then_with(|| a.name.to_lowercase().cmp(&b.name.to_lowercase()))
    });
    Ok(entries)
}

pub fn list_local_directory_json(root: &str) -> Result<String> {
    serde_json::to_string(&list_local_directory(root)?).context("failed to encode local entries")
}

pub fn is_video_path(path: &Path) -> bool {
    path.extension()
        .and_then(|value| value.to_str())
        .map(|value| VIDEO_EXTENSIONS.contains(&value.to_ascii_lowercase().as_str()))
        .unwrap_or(false)
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::path::PathBuf;

    #[test]
    fn filters_video_extensions() {
        assert!(is_video_path(&PathBuf::from("movie.mkv")));
        assert!(is_video_path(&PathBuf::from("movie.MP4")));
        assert!(!is_video_path(&PathBuf::from("cover.jpg")));
    }
}
