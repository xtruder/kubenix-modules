# Mediawiki setup

## CirrusSearch

- Allow elasticsearch to create more than 1000 fields

```
curl -XPUT mediawiki-elasticsearch:9200/_template/template_1 -d '{"template": "mediawiki*", "settings":{"index.mapping.total_fields.limit": 10000}}'
```

- Reindex

```
php extensions/CirrusSearch/maintenance/updateSearchIndexConfig.php
```
