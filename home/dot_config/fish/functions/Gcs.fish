function Gcs --description "Open GCS bucket with browser"
    set -l gcs_bucket (string replace "gs://" "" $argv[1])
    xdg-open https://console.cloud.google.com/storage/browser/$gcs_bucket
end
