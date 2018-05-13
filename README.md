# MicrobiomeDB Shiny Apps

## Prerequisite

* data.table (tested with version 1.10.4.3)
* phyloseq (tested with version 1.22.3)
* shiny (tested with version 1.0.5)
* biom (tested with version 0.4.0)
* DESeq2 (tested with version 1.12.4)

## How to configure before running the apps

1. Change the common/config.R file with the path to the biom file and the metadata details file:

biom_file <- "path_to_your_biom"

metadata_details <- "path_to_your_metadata_details"

1.1. The metadata_details file should be a tabular file with the selection of metadata to be used and the data type of each metadata. Example:

```
Property	Type
age	number
antibiotics	text
body_site	text
sex	text
weight_kg	number
```

## How to run the apps

Each shiny app run separately and you can use the command line to launch an app:

```
R -e "shiny::runApp('~/Projects/microbiomedb/abundance_app')"
```

You can customize the runApp function providing different parameters, e.g. appDir, port, host, etc. See [the official documentation for more details](https://shiny.rstudio.com/reference/shiny/0.11/runApp.html).

