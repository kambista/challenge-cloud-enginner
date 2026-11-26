terraform {
  backend "gcs" {
    bucket = "proyect-kambista-challenge-tfstate"
    prefix = "bootstrap"
  }
}
