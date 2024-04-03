bq load \
    --source_format=NEWLINE_DELIMITED_JSON \
    --autodetect --ignore_unknown_values --max_bad_records 1000  \
    usage_stats_dataset.production \
    sample.json

# vacuum the table

bq query --use_legacy_sql=false 'DELETE FROM usage_stats_dataset.production WHERE TRUE'

# load in full

bq load \
    --source_format=NEWLINE_DELIMITED_JSON \
    --ignore_unknown_values  \
    usage_stats_dataset.production \
    "gs://vllm-usage-stats/*"
