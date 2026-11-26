terraform {
  backend "gcs" {
    bucket = "kambista-quotes-reto-tfstate"
    prefix = "terraform/state"
  }
}