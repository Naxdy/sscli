use std::collections::HashMap;

use eyre::{Context, ContextCompat, Result};
use secret_service::SecretService;

fn parse_props(props: Vec<String>) -> Result<HashMap<String, String>> {
    props
        .into_iter()
        .map(|e| {
            let split = e.split("=").collect::<Vec<_>>();

            Ok::<(String, String), eyre::Error>((
                split
                    .first()
                    .context("Missing key/value assignment")?
                    .to_string(),
                split
                    .get(1)
                    .context("Missing key/value assignment")?
                    .to_string(),
            ))
        })
        .collect::<Result<HashMap<String, String>, _>>()
}

pub async fn get_secret(ss: SecretService<'_>, props: Vec<String>) -> Result<String> {
    let props = parse_props(props).context("Failed to parse props argument")?;

    let collection = ss
        .get_default_collection()
        .await
        .context("Failed to get secret service collection")?;

    let items = collection
        .search_items(props.iter().map(|e| (e.0.as_str(), e.1.as_str())).collect())
        .await
        .context("Failed to search collection for items")?;

    if let Some(item) = items.first() {
        Ok(String::from_utf8(
            item.get_secret()
                .await
                .context("Failed to retrieve secret")?,
        )
        .context("Failed to parse secret to UTF8")?)
    } else {
        Err(eyre::eyre!("Could not find matching secret"))
    }
}
