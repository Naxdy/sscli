mod get_entry;

use clap::{Parser, Subcommand};
use get_entry::get_secret;
use secret_service::SecretService;

#[derive(Parser, Debug)]
struct Cli {
    #[command(subcommand)]
    command: Command,
}

#[derive(Subcommand, Debug)]
enum Command {
    /// Retrieve an entry from the secret service, according to a list of props
    GetEntry {
        /// List of properties to search the entry for, specified as key=value
        #[arg(short, long)]
        props: Vec<String>,
    },
}

#[tokio::main]
async fn main() -> eyre::Result<()> {
    let cli = Cli::parse();

    let ss = SecretService::connect(secret_service::EncryptionType::Dh)
        .await
        .expect("Failed to connect to secret service");

    match cli.command {
        Command::GetEntry { props } => {
            let secret = get_secret(ss, props).await?;

            print!("{secret}");
        }
    }

    Ok(())
}
