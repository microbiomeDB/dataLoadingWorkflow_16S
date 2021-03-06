library(data.table)
library(dada2)

args <- commandArgs(TRUE)

filesDir <- args[1]
taxonRefFile <- args[2]

myFiles <- list.files(filesDir, pattern = ".tab" , full.names = TRUE)
if (length(myFiles) > 1) {
  myMerge <- function(x,y) {
    #if not a data.table then assume its a string containing a path to a file
    if (!is.data.table(x)) {
      x <- fread(x)
    }
    if (!is.data.table(y)) {
      y <- fread(y)
    }
    out <- merge(x,y, all = TRUE, by = "V1")
  }
  
  asvTable <- Reduce(myMerge, myFiles)
  
  asvTable[is.na(asvTable)] <- 0
  
  file.remove(myFiles)
} else {
  message("only one tab file... renaming to final_featureTable.tab.")
  asvTable <- fread(myFiles[1])
  asvTable[is.na(asvTable)] <- 0
  file.remove(myFiles[1])
}

seqs <- asvTable$V1
taxa <- assignTaxonomy(seqs, taxonRefFile)
taxa <- as.data.table(taxa, keep.rownames=TRUE)
colnames(taxa)[colnames(taxa) == "rn"] <- "V1"

finalTable <- merge(taxa, asvTable, by = "V1")
finalTable$V1 <- NULL
finalTable$taxaString <- paste0(finalTable$Kingdom, ";", finalTable$Phylum, ";", finalTable$Class, ";", finalTable$Order, ";", finalTable$Family, ";", finalTable$Genus, ";", finalTable$Species)
finalTable[,c("Kingdom", "Phylum", "Class", "Order", "Family", "Genus", "Species") := NULL]
#moves taxaString col from last to first
setcolorder(test, c("taxaString", colnames(test)[1:ncol(test)-1]))

write.table(finalTable, file = file.path(filesDir, "final_featureTable.tab"), quote=FALSE, sep = '\t', col.names = NA)