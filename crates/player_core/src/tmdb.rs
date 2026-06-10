use anyhow::Result;
use reqwest::Client;
use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub enum TmdbMediaType {
    Movie,
    Tv,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct TmdbSearchItem {
    pub id: u64,
    pub media_type: TmdbMediaType,
    pub title: String,
    pub original_title: Option<String>,
    pub overview: Option<String>,
    pub poster_path: Option<String>,
    pub backdrop_path: Option<String>,
    pub release_date: Option<String>,
    pub vote_average: Option<f32>,
}

#[derive(Clone)]
pub struct TmdbClient {
    http: Client,
    access_token: String,
    language: String,
    api_base_url: String,
}

impl TmdbClient {
    pub fn new(
        access_token: impl Into<String>,
        language: impl Into<String>,
        api_base_url: impl Into<String>,
    ) -> Self {
        Self {
            http: Client::new(),
            access_token: access_token.into(),
            language: language.into(),
            api_base_url: normalize_base_url(api_base_url.into()),
        }
    }

    pub async fn search_movie(
        &self,
        query: &str,
        year: Option<u16>,
    ) -> Result<Vec<TmdbSearchItem>> {
        let mut request = self
            .http
            .get(format!("{}/search/movie", self.api_base_url))
            .bearer_auth(&self.access_token)
            .query(&[
                ("query", query.to_string()),
                ("language", self.language.clone()),
                ("include_adult", "false".to_string()),
                ("page", "1".to_string()),
            ]);

        if let Some(year) = year {
            request = request.query(&[("year", year.to_string())]);
        }

        let response: MovieSearchResponse =
            request.send().await?.error_for_status()?.json().await?;
        Ok(response
            .results
            .into_iter()
            .map(|item| TmdbSearchItem {
                id: item.id,
                media_type: TmdbMediaType::Movie,
                title: item.title,
                original_title: item.original_title,
                overview: item.overview,
                poster_path: item.poster_path,
                backdrop_path: item.backdrop_path,
                release_date: item.release_date,
                vote_average: item.vote_average,
            })
            .collect())
    }

    pub async fn search_tv(&self, query: &str, year: Option<u16>) -> Result<Vec<TmdbSearchItem>> {
        let mut request = self
            .http
            .get(format!("{}/search/tv", self.api_base_url))
            .bearer_auth(&self.access_token)
            .query(&[
                ("query", query.to_string()),
                ("language", self.language.clone()),
                ("include_adult", "false".to_string()),
                ("page", "1".to_string()),
            ]);

        if let Some(year) = year {
            request = request.query(&[("first_air_date_year", year.to_string())]);
        }

        let response: TvSearchResponse = request.send().await?.error_for_status()?.json().await?;
        Ok(response
            .results
            .into_iter()
            .map(|item| TmdbSearchItem {
                id: item.id,
                media_type: TmdbMediaType::Tv,
                title: item.name,
                original_title: item.original_name,
                overview: item.overview,
                poster_path: item.poster_path,
                backdrop_path: item.backdrop_path,
                release_date: item.first_air_date,
                vote_average: item.vote_average,
            })
            .collect())
    }

    pub fn poster_url(path: &str, size: &str) -> String {
        format!("https://image.tmdb.org/t/p/{size}{path}")
    }
}

fn normalize_base_url(value: String) -> String {
    value.trim_end_matches('/').to_string()
}

#[derive(Debug, Deserialize)]
struct MovieSearchResponse {
    results: Vec<MovieSearchResult>,
}

#[derive(Debug, Deserialize)]
struct MovieSearchResult {
    id: u64,
    title: String,
    original_title: Option<String>,
    overview: Option<String>,
    poster_path: Option<String>,
    backdrop_path: Option<String>,
    release_date: Option<String>,
    vote_average: Option<f32>,
}

#[derive(Debug, Deserialize)]
struct TvSearchResponse {
    results: Vec<TvSearchResult>,
}

#[derive(Debug, Deserialize)]
struct TvSearchResult {
    id: u64,
    name: String,
    original_name: Option<String>,
    overview: Option<String>,
    poster_path: Option<String>,
    backdrop_path: Option<String>,
    first_air_date: Option<String>,
    vote_average: Option<f32>,
}
