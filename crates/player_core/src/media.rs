use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub enum MediaKind {
    Movie,
    TvEpisode,
    Unknown,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct MediaIdentity {
    pub raw_title: String,
    pub normalized_title: String,
    pub year: Option<u16>,
    pub season: Option<u16>,
    pub episode: Option<u16>,
    pub kind: MediaKind,
}

pub fn parse_media_identity(folder_name: &str, file_name: &str) -> MediaIdentity {
    let basename = strip_extension(file_name);
    let raw_title = format!("{folder_name} {basename}");
    let raw_tokens = tokenize(&raw_title);
    let year = parse_year(&raw_tokens);
    let (mut season, mut episode) = parse_season_episode(&raw_title);
    let inferred_episode = season.is_none()
        && episode.is_none()
        && !folder_name.trim().is_empty()
        && infer_episode_from_numeric_basename(basename).is_some();

    if inferred_episode {
        season = Some(1);
        episode = infer_episode_from_numeric_basename(basename);
    }

    let title_source = if inferred_episode {
        folder_name
    } else {
        raw_title.as_str()
    };

    let normalized_title = tokenize(title_source)
        .into_iter()
        .filter(|token| !is_noise_token(token))
        .filter(|token| parse_year(&[token.to_string()]).is_none())
        .filter(|token| !is_episode_token(token))
        .collect::<Vec<_>>()
        .join(" ")
        .trim()
        .to_string();

    let kind = if season.is_some() || episode.is_some() {
        MediaKind::TvEpisode
    } else if !normalized_title.is_empty() {
        MediaKind::Movie
    } else {
        MediaKind::Unknown
    };

    MediaIdentity {
        raw_title,
        normalized_title,
        year,
        season,
        episode,
        kind,
    }
}

fn strip_extension(file_name: &str) -> &str {
    file_name
        .rsplit_once('.')
        .map(|(name, _)| name)
        .unwrap_or(file_name)
}

fn tokenize(input: &str) -> Vec<String> {
    input
        .chars()
        .map(|ch| match ch {
            '.' | '_' | '-' | '[' | ']' | '(' | ')' => ' ',
            _ => ch,
        })
        .collect::<String>()
        .split_whitespace()
        .map(|part| part.trim().to_string())
        .filter(|part| !part.is_empty())
        .collect()
}

fn parse_year(tokens: &[String]) -> Option<u16> {
    tokens.iter().find_map(|token| {
        let year = token.parse::<u16>().ok()?;
        (1888..=2100).contains(&year).then_some(year)
    })
}

fn parse_season_episode(input: &str) -> (Option<u16>, Option<u16>) {
    let lower = input.to_ascii_lowercase();
    let bytes = lower.as_bytes();

    for index in 0..bytes.len() {
        if bytes[index] == b's' {
            let season_start = index + 1;
            let (season, consumed) = parse_one_or_two_digits(&lower[season_start..]);
            let e_index = season_start + consumed;
            if season.is_some() && bytes.get(e_index) == Some(&b'e') {
                let (episode, _) = parse_one_or_two_digits(&lower[e_index + 1..]);
                return (season, episode);
            }
        }
    }

    (None, None)
}

fn parse_one_or_two_digits(input: &str) -> (Option<u16>, usize) {
    let digits = input
        .chars()
        .take(2)
        .take_while(|ch| ch.is_ascii_digit())
        .collect::<String>();

    let consumed = digits.len();
    (digits.parse::<u16>().ok(), consumed)
}

fn infer_episode_from_numeric_basename(input: &str) -> Option<u16> {
    let digits = input
        .trim_start()
        .chars()
        .take(3)
        .take_while(|ch| ch.is_ascii_digit())
        .collect::<String>();
    let value = digits.parse::<u16>().ok()?;
    (1..=999).contains(&value).then_some(value)
}

fn is_episode_token(token: &str) -> bool {
    let lower = token.to_ascii_lowercase();
    if lower.starts_with('s') && lower.contains('e') {
        return true;
    }
    false
}

fn is_noise_token(token: &str) -> bool {
    matches!(
        token.to_ascii_lowercase().as_str(),
        "2160p"
            | "1080p"
            | "720p"
            | "480p"
            | "webrip"
            | "web"
            | "web-dl"
            | "bluray"
            | "bdrip"
            | "x264"
            | "x265"
            | "h264"
            | "h265"
            | "hevc"
            | "aac"
            | "ddp"
            | "dts"
            | "hdr"
            | "dv"
            | "remux"
    )
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parses_movie_title() {
        let identity =
            parse_media_identity("Inception (2010)", "Inception.2010.1080p.BluRay.x265.mkv");

        assert_eq!(identity.year, Some(2010));
        assert_eq!(identity.kind, MediaKind::Movie);
        assert!(identity.normalized_title.contains("Inception"));
    }

    #[test]
    fn parses_tv_episode() {
        let identity = parse_media_identity("Breaking Bad", "Breaking.Bad.S01E02.1080p.mkv");

        assert_eq!(identity.kind, MediaKind::TvEpisode);
        assert_eq!(identity.season, Some(1));
        assert_eq!(identity.episode, Some(2));
    }

    #[test]
    fn parses_single_digit_tv_episode() {
        let identity = parse_media_identity("Show", "Show.S1E2.mkv");

        assert_eq!(identity.kind, MediaKind::TvEpisode);
        assert_eq!(identity.season, Some(1));
        assert_eq!(identity.episode, Some(2));
    }

    #[test]
    fn infers_episode_from_numeric_file_in_series_folder() {
        let identity = parse_media_identity("Example Show", "01~4K.mp4");

        assert_eq!(identity.kind, MediaKind::TvEpisode);
        assert_eq!(identity.normalized_title, "Example Show");
        assert_eq!(identity.season, Some(1));
        assert_eq!(identity.episode, Some(1));
    }

    #[test]
    fn infers_episode_from_plain_numeric_file_in_series_folder() {
        let identity = parse_media_identity("Example Show", "2.mp4");

        assert_eq!(identity.kind, MediaKind::TvEpisode);
        assert_eq!(identity.normalized_title, "Example Show");
        assert_eq!(identity.season, Some(1));
        assert_eq!(identity.episode, Some(2));
    }
}
