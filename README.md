# MicrobiomeDB data loading workflow for handling Illumina 16S rRNA sequencing data

This repo contains the scripts used to process raw .fastq files from Illumina 16S rRNA microbiome studies prior to loading into microbiomeDB.

## Prerequisite R packages

* dada2
* data.table
* shortread


## Scripts

* **ASVTableTask.pm** - runs the job on a cluster
* **demuxAndBuildErrorModels.R** - builds error model used for denoising of sequences during dada2
* **runDada.R** - denoises sequences to generate an abundance table of 100% OTUs, or Amplicon Sequence Variants (ASV) 
