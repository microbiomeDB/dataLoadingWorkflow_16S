source("https://bioconductor.org/biocLite.R")
library(data.table)
library(ShortRead)
library(dada2)


#!#!#!#!#!#!#!#!#!#!#!#!#!#!#!#!# ARGUMENTS #!#!#!#!#!#!#!#!#!#!#!#!#!#!#!#!#!#!#!#!#

args <- commandArgs(TRUE)

dataDir <- args[1]
if (dataDir == 'none') {
  dataDir <- NULL
}
inputDir <- args[2]
if (inputDir == 'none') {
  inputDir <- NULL
}
forwardReads <- args[3]
if (forwardReads == 'none') {
  forwardReads <- NULL
}
reverseReads <- args[4]
if (reverseReads == 'none') {
  reverseReads <- NULL
}
forwardBarcodes <- args[5]
if (forwardBarcodes == 'none') {
  forwardBarcodes <- NULL
}
reverseBarcodes <- args[6]
if (reverseBarcodes == 'none') {
  reverseBarcodes <- NULL
}
multiplexed <- args[7]
if (multiplexed == 'true') {
  multiplexed <- TRUE
} else {
  multiplexed <- FALSE
}
barcodesType <- args[8]
samplesInfo <- args[9]
if (samplesInfo == 'none') {
  samplesInfo <- NULL
}
isPaired <- args[10]
if (isPaired == 'true') {
  isPaired <- TRUE
} else {
  isPaired <- FALSE
}
trimLeft <- args[11]
if (trimLeft == 'none') {
  trimLeft = 0
}
trimLeftR <- args[12]
if (trimLeftR == 'none') {
  trimLeftR = 0
}
truncLen <- args[13]
truncLenR <- args[14]
#need either the four above OR this below to determine the four above
readLen <- args[15]
#can pass this through later if we decide to add support for 454 or IT, for now written in as Illumina
dataType = "Illumina"
#if we want to specify a number of threads rather than use all available or some default then add an argument

if (is.null(samplesInfo)) {
  samples.info <- NULL
} else {
  samples.info <- fread(samplesInfo)
}


#these functions could move to seperate file and be sourced instead

#!#!#!#!#!#!#!#!#!#!#!#!#!#!#!#!#!# FUNCTIONS !#!#!#!#!#!#!#!#!#!#!#!#!#!#!#!#!#!#!#

#returns AlignedRead object for barcodesType 'independant', so that barcode can be stored under the alignData slot
importIlluminaData <- function(readsFile = NULL, barcodesFile = NULL, barcodesType = NULL, isPaired = NULL) {
  message("importing illumina data...")
  #read in as shortreadq obj
  seqs <- readFastq(readsFile)
  #grab out info necessary to build alignedread obj as input to demux
  seqs.quality <- quality(seqs)
  seqs.id <- id(seqs)
  seqs <- sread(seqs)
  
  if (barcodesType == "independant") {
    #read in barcodes as shortreadq obj
    barcodes <- readFastq(barcodesFile)
    #barcodes saved as character vector
    barcodes <- as.data.frame(sread(barcodes))
    colnames(barcodes) <- "multiplexIndex"
    metadata <- AlignedDataFrame(barcodes)
    
    #building alignedread obj
    alignedSeqs <- AlignedRead(seqs, seqs.id, seqs.quality, alignData = metadata)
  } else {
    seqs
  }
}

#choosing not to set defaults here, defaults set in perl code for cluster task
demultiplex <- function(data = NULL, dataDir = NULL, barcodesType = NULL, barcodes = NULL, sampleNames = NULL, suffix = "") {
  
  #TODO also look into dual indeces (spelling??)
  
  if (!is.null(barcodes)) {
    numBarcodes <- length(barcodes)
    lengthBarcodes <- nchar(barcodes[1])
    message("running internal demux...")
    demux <- demux(data, barcodes = barcodes, barcodes.qty = numBarcodes, barcode.length = lengthBarcodes, type=barcodesType)
  } else {
    #if we want to infer barcodes within reads will need additional param to specify barcode length and number to know what to look for
    demux <- demux(data, type=barcodesType)
  }
  
  #TODO once the 'within' half of demux function is working from here below may need revisiting because it uses a different data type
  #i dont know what exactly it will need yet cause i dont have a dataset to test it
  demuxAlignedSeqs <- demux[1]$reads
  unlink(file.path(dataDir, "demux"), recursive = TRUE)
  dir.create(file.path(dataDir, "demux"))
  
  count=1
  #convert back to shortreadQ for writing to seperate fastq
  for (i in demuxAlignedSeqs) {
    seqs <- sread(i)
    seqs.quality <- quality(i)
    seqs.id <- id(i)
    
    srQ <- ShortReadQ(sread = seqs, quality = seqs.quality, id = seqs.id)
    if (!is.null(sampleNames)) {
      myPath <- paste0(file.path(dataDir, "demux/"), sampleNames[barcodes == names(demuxAlignedSeqs[count])], suffix, ".fastq")
    } else {
      myPath <- paste0(file.path(dataDir, "demux/"), barcodes[barcodes == names(demuxAlignedSeqs[count])], suffix, ".fastq")
    }
    writeFastq(srQ, myPath)
    count = count + 1
  }
  
}

buildErrors <- function(files = NULL, errFile = NULL, dataType = NULL, readType = NULL, truncLen = NULL, truncLenR = NULL,
                        trimLeft = NULL, trimLeftR = NULL) {
  
  unlink(errFile)
  if (dataType == "Illumina") {
    if (isPaired == FALSE) {
      message("running as single end...")
      asvTable <- ilSingleErr(files, errFile, truncLen = truncLen, trimLeft = trimLeft)
    } else {
      asvTable <- ilPairedErr(files, errFile, truncLen = truncLen, trimLeft = trimLeft,
                              truncLenR = truncLenR, trimLeftR = trimLeftR)
    }
  } else {
    stop("Illumina is currently the only supported data type... check back later.")
  }
}

ilSingleErr <- function(files = NULL, errFile = NULL, truncLen = NULL, trimLeft = NULL) {
  
  if (length(files) == 1) {
    #create filtered dir and paths from a given dir
    unfilts <- sort(list.files(files, pattern=".fastq", full.names = TRUE))
    sample.names <- sapply(strsplit(basename(unfilts), ".fastq"), `[`, 1)
    filt.path <- file.path(files, "filtered")
    filts <- file.path(filt.path, paste0(sample.names, "_filt.fastq"))
  } else {
    unfilts <- files
    #create filtered dir and paths from list of files
    sample.names <- sapply(strsplit(basename(files), ".fastq"), `[`, 1)
    filt.path <- file.path(dirname(files[1]), "filtered")
    filts <- file.path(filt.path, paste0(sample.names, "_filt.fastq"))
  }
  unlink(filt.path, recursive = TRUE)
  ## TRIM AND FILTER ###
  out <- suppressWarnings(filterAndTrim(unfilts, filts, truncLen=truncLen, trimLeft=trimLeft,
                                        maxEE=2, truncQ=2, rm.phix=TRUE, multithread=1))
  filts <- list.files(filt.path, pattern=".fastq", full.names=TRUE)
  if(length(filts) == 0) {
    stop("No reads passed the filter (was truncLen longer than the read length?)")
  }
  
  ### LEARN ERROR RATES ###
  # Dereplicate enough samples to get 1 million total unique reads to model errors on
  NREADS <- 0
  drps <- vector("list", length(filts))
  for(i in seq_along(filts)) {
    drps[[i]] <- derepFastq(filts[[i]])
    NREADS <- NREADS + sum(drps[[i]]$uniques)
    if(NREADS > 1000000) { break }
  }
  # Run dada in self-consist mode on those samples
  dds <- vector("list", length(filts))
  
  if(i==1) { # breaks list assignment
    dds[[1]] <- dada(drps[[1]], err=NULL, selfConsist=TRUE, multithread=1)#,
    #       VECTORIZED_ALIGNMENT=FALSE)
  } else { # more than one sample, no problem with list assignment
    dds[1:i] <- dada(drps[1:i], err=NULL, selfConsist=TRUE, multithread=1)#,
    #VECTORIZED_ALIGNMENT=FALSE)
  }
  #message(dds)
  err <- dds[[1]]$err_out
  #message(err)
  rm(drps)
  
  #remove filt files for error models so they dont get redone as subtasks
  file.remove(filts[1:i])
  
  #save err file for use with remaining samples later
  saveRDS(err,errFile)
  
  #make an asvtable for the already processed samples.
  #names(dds[1:i]) <- sample.names[1:i]
  seqtab <- makeSequenceTable(dds[1:i])
  rownames(seqtab) <- sample.names[1:i]
  seqtab.nochim <- removeBimeraDenovo(seqtab, method="consensus",
                                      minFoldParentOverAbundance=1,
                                      multithread=1)
  
  return(as.data.frame(t(seqtab.nochim)))
}

ilPairedErr <- function(files = NULL, errFile = NULL, truncLen = NULL, trimLeft = NULL,
                        truncLenR = NULL, trimLeftR = NULL) {
  
  if (length(files) == 1) {
    unfiltsF <- sort(list.files(files, pattern="_R1_001.fastq", full.names = TRUE))
    unfiltsR <- sort(list.files(files, pattern="_R2_001.fastq", full.names = TRUE))
    # Extract sample names, assuming filenames have format: SAMPLENAME_XXX.fastq
    sample.names <- sapply(strsplit(basename(unfiltsF), "_"), `[`, 1)
    filt.path <- file.path(files, "filtered")
    filtsF <- file.path(filt.path, basename(unfiltsF))
    filtsR <- file.path(filt.path, basename(unfiltsR))
  } else {
    unfiltsF <- files[grep("_R1_001",files)]
    unfiltsR <- files[grep("_R2_001", files)]
    sample.names <- sapply(strsplit(basename(unfiltsF), "_"), `[`, 1)
    filt.path <- file.path(dirname(files[1]), "filtered")
    filtsF <- file.path(filt.path, basename(unfiltsF))
    filtsR <- file.path(filt.path, basename(unfiltsR))
  }
  
  unlink(filt.path, recursive = TRUE)
  ### TRIM AND FILTER ###
  message("filter and trimming...")
  out <- suppressWarnings(filterAndTrim(unfiltsF, filtsF, unfiltsR, filtsR,
                                        truncLen=c(truncLen, truncLenR), trimLeft=c(trimLeft, trimLeftR),
                                        maxEE=c(2,2), truncQ=2, rm.phix=TRUE,
                                        multithread=1))
  filtsF <- list.files(filt.path, pattern="_R1_001.fastq", full.names=TRUE)
  filtsR <- list.files(filt.path, pattern="_R2_001.fastq", full.names=TRUE)
  if(length(filtsF) == 0) { # All reads were filtered out
    stop("No reads passed the filter (were truncLenF/R longer than the read lengths?)")
  }
  message("learning error rates...")
  ### LEARN ERROR RATES ###
  # Dereplicate enough samples to get 1 million total reads
  NREADS <- 0
  drpsF <- vector("list", length(filtsF))
  drpsR <- vector("list", length(filtsR))
  denoisedF <- rep(0, length(filtsF))
  getN <- function(x) sum(getUniques(x))
  for(i in seq_along(filtsF)) {
    drpsF[[i]] <- derepFastq(filtsF[[i]])
    drpsR[[i]] <- derepFastq(filtsR[[i]])
    NREADS <- NREADS + sum(drpsF[[i]]$uniques)
    if(NREADS > 1000000) { break }
  }
  # Run dada in self-consist mode on those samples
  drpsF <- drpsF[1:i]
  drpsR <- drpsR[1:i]
  ddsF <- dada(drpsF, err=NULL, selfConsist=TRUE, multithread=1)#,
  #VECTORIZED_ALIGNMENT=FALSE)
  ddsR <- dada(drpsR, err=NULL, selfConsist=TRUE, multithread=1)#,
  #VECTORIZED_ALIGNMENT=FALSE)
  if(i==1) {
    errF <- ddsF$err_out
    errR <- ddsR$err_out
  } else {
    errF <- ddsF[[1]]$err_out
    errR <- ddsR[[1]]$err_out
  }
  
  #remove filts files for err model so they dont get redone as subtasks
  file.remove(filtsF[1:i])
  file.remove(filtsR[1:i])
  
  #save err file for use with remaining samples
  err <- c(errF,errR)
  saveRDS(err,errFile)
  
  mergers <- vector("list", length(filtsF))
  if(i==1) { # breaks list assignment
    mergers[[1]] <- mergePairs(ddsF, drpsF, ddsR, drpsR)
    denoisedF[[1]] <- getN(ddsF)
  } else {
    mergers[1:i] <- mergePairs(ddsF, drpsF, ddsR, drpsR)
    denoisedF[1:i] <- sapply(ddsF, getN)
  }
  rm(drpsF); rm(drpsR); rm(ddsF); rm(ddsR)
  #make an asvtable for the already processed samples.
  names(mergers[1:i]) <- sample.names[1:i]
  seqtab <- makeSequenceTable(mergers[1:i])
  
  seqtab.nochim <- removeBimeraDenovo(seqtab, method="consensus",
                                      minFoldParentOverAbundance=1,
                                      multithread=1)
  
  return(as.data.frame(t(seqtab.nochim)))
}

".getBpParam" <- function(mc.cores=1L){
  return(switch(as.character(mc.cores),
                "1"=SerialParam(),
                MulticoreParam(workers=mc.cores)))
}

setGeneric(name="demux",
           def=function(obj,
                        barcodes=c(),
                        barcodes.qty=12,
                        barcode.length=6,
                        edition.dist=2,
                        type="independant",
                        index.only=FALSE,
                        mc.cores=1L){
             standardGeneric("demux")
           })

setMethod(
  f="demux",
  signature="AlignedRead",
  definition=function(obj,barcodes=c(),
                      barcodes.qty=12,
                      barcode.length=6,
                      edition.dist=2,
                      type="independant",
                      index.only=FALSE,
                      mc.cores=1L){
    
    ## check the input
    types <- eval(formals("demux")$type)
    if(!type %in% types){
      stop(paste(
        "The given type:",
        type,
        "is not part of the supported types:",
        paste(types,collapse=", ")))
    }
    
    ## do we have barcodes
    if(length(barcodes)==0){
      barcodes <- switch(type,
                         independant=as.character(as.data.frame(sort(table(
                           alignData(obj)$multiplexIndex),
                           decreasing=TRUE)[1:barcodes.qty])[,1]),
                         within=as.character(as.data.frame(sort(table(
                           as.character(narrow(sread(obj),start=1,
                                               width=barcode.length))),
                           decreasing=TRUE)[1:barcodes.qty])[,1])
      )
    } else {
      if(length(unique(nchar(barcodes)))!=1){
        stop("We accept only barcodes having the same length.")
      }
      if(!all(nchar(barcodes) == barcode.length)){
        warning(paste("The provided barcode length was not correct.",
                      "Set it to:",nchar(barcodes[1])))
        barcode.length=nchar(barcodes[1])
      }
    }
    ## get the barcodes, according to a certain size
    all.barcodes <- switch(type,
                           independant=DNAStringSet(
                             as.character(alignData(obj)$multiplexIndex)),
                           within=narrow(sread(obj),start=1,
                                         width=barcode.length)
    )
    
    unique.barcodes <- switch(type,
                              independant=DNAStringSet(
                                as.character(unique(alignData(obj)$multiplexIndex))),
                              within=unique(narrow(sread(obj),start=1,
                                                   width=barcode.length))
    )
    
    ## just for illumina
    if(type=="independant" & nchar(all.barcodes)[1] > barcode.length){
      all.barcodes <- narrow(all.barcodes,start=1,width=barcode.length)
    }
    dist <- do.call(cbind, srdistance(all.barcodes, barcodes, BPPARAM=.getBpParam(mc.cores)))
    
    ## create a selector per barcode
    sels <- lapply(barcodes,
                   function(barcode,dist,edition.dist){
                     i.sel <- colnames(dist)==barcode
                     dist[,i.sel]<=edition.dist & eval(parse(text=paste(paste("dist[,",which(!i.sel),"] > edition.dist",collapse=" & "))))
                   },dist,edition.dist)
    
    ## validate
    if(sum(sapply(sels,sum))>length(all.barcodes)){
      warning(
        paste(
          "You have more reads selected: ",sapply(sels,sum),"using the edition distance:",
          edition.dist,"than you have reads:",length(all.barcodes),"!\nUse the barcodePlot function to visually assess it."))
    }
    ## select barcodes
    names(sels)<-colnames(dist)
    
    ## either the alns or the sels are returned
    if(index.only){
      return(sels)
    } else {
      ## original read length
      read.length <- width(obj)[1]
      
      ## return a lists of aln
      alns <- lapply(barcodes,function(barcode,obj,sels){
        reads <- narrow(obj[sels[[barcode]]],start=barcode.length+1,width=read.length-barcode.length)
        bars <- narrow(obj[sels[[barcode]]],start=1,width=barcode.length)
        return(list(reads=reads,bars=bars))
      },obj,sels)
      names(alns) <- colnames(dist)
      alns <- list(reads=lapply(alns,function(x){x[[1]]}),barcodes=lapply(alns,function(x){sread(x[[2]])}))
      return(alns)
    }
  })

setMethod(
  f="demux",
  signature="DNAStringSet",
  definition=function(obj,barcodes=c(),
                      barcodes.qty=12,
                      barcode.length=6,
                      edition.dist=2,
                      type=c("independant","within"),
                      index.only=FALSE,
                      mc.cores=1L){
    
    ## There's only one possible type!!
    if(type=="independant"){
      stop(paste("We cannot accept the independant argument for a ",class(obj),", since we miss the barcode sequences",sep=""))
    }
    
    ## check the input
    types <- eval(formals("demultiplex")$type)[-1]
    if(!type %in% types){
      stop(paste(
        "The given type:",
        type,
        "is not part of the supported types:",
        paste(types,collapse=", ")))
    }
    
    ## do we have barcodes
    if(length(barcodes)==0){
      barcodes <- as.character(as.data.frame(sort(table(
        as.character(narrow(sread(obj),start=1,
                            width=barcode.length))),
        decreasing=TRUE)[1:barcodes.qty])[,1])
    } else {
      if(length(unique(nchar(barcodes)))!=1){
        stop("We accept only barcodes having the same length.")
      }
      if(!all(nchar(barcodes) == barcode.length)){
        warning(paste("The provided barcode length was not correct.",
                      " Set it to:",nchar(barcodes[1])))
        barcode.length=nchar(barcodes[1])
      }
    }
    
    ## get the barcodes, according to a certain size
    all.barcodes <-narrow(obj,start=1,width=barcode.length)
    dist <- do.call(cbind, srdistance(all.barcodes, barcodes, BPPARAM=.getBpParam(mc.cores)))
    
    ## create a selector per barcode
    sels <- lapply(barcodes,
                   function(barcode,dist,edition.dist){
                     i.sel <- colnames(dist)==barcode
                     dist[,i.sel]<=edition.dist & eval(parse(text=paste(paste("dist[,",which(!i.sel),"] > edition.dist",collapse=" & "))))
                   },dist,edition.dist)
    
    ## validate
    if(sum(sapply(sels,sum))>length(all.barcodes)){
      warning(
        paste(
          "You have more reads selected: ",sapply(sels,sum),"using the edition distance:",
          edition.dist,"than you have reads:",length(all.barcodes),"!\nUse the barcodePlot function to visually assess it."))
    }
    ## select barcodes
    names(sels)<-colnames(dist)
    
    ## either the alns or the sels are returned
    if(index.only){
      return(sels)
    } else {
      ## original read length
      read.length <- width(obj)[1]
      
      ## return a lists of aln
      alns <- lapply(barcodes,function(barcode,obj,sels){
        reads <- narrow(obj[sels[[barcode]]],start=barcode.length+1,width=read.length-barcode.length)
        bars <- narrow(obj[sels[[barcode]]],start=1,width=barcode.length)
        return(list(reads=reads,bars=bars))
      },obj,sels)
      names(alns) <- colnames(dist)
      alns <- list(reads=lapply(alns,function(x){x[[1]]}),barcodes=lapply(alns,function(x){x[[2]]}))
      return(alns)
    }
  })

setMethod(
  f="demux",
  signature="ShortReadQ",
  definition=function(obj,barcodes=c(),
                      barcodes.qty=12,
                      barcode.length=6,
                      edition.dist=2,
                      type=c("independant","within"),
                      index.only=FALSE,
                      mc.cores=1L){
    return(
      demultiplex(sread(obj),barcodes=barcodes,barcodes.qty=barcodes.qty,barcode.length=barcode.length, edition.dist=edition.dist, type=type,index.only=index.only)
    )
  })

findTruncLen = function(forwardReads = NULL, reverseReads = NULL, sample_size = 10000, readLen = NULL, expected_errors = 2, overlap = 20) {
  
  if (!is.null(reverseReads)) {
    lengths <- data.frame("forward"=c(NA),"reverse"=c(NA))
  } else {
    lengths <- data.frame("forward"=c(NA))
  } 
  
  numSamples <- length(forwardReads)
  if (numSamples < 50) {
    numSamplesToUse <- numSamples
  } else {
    numSamplesToUse <- floor(numSamples/10)
  }
  
  for (x in sample(x=seq(numSamples),numSamplesToUse)) {
    
    fqFile <- forwardReads[x]
    reads <- readFastq(fqFile)  
    
    if(sample_size > length(sread(reads))) {
      sample_size <- length(sread(reads))
    }
    
    ## Extract the quality on random subset and calculate the expected error for each sequence
    qual <- as(quality(reads[sample(x = seq(1,length(sread(reads))), size = sample_size, replace = F)]), "matrix")
    qual[is.na(qual)] <- 0 
    error <- 10^(-1*qual/10)
    summed <- apply(error, 1, cumsum)
    
    ## Select reads with less expected errors than the threshold
    trunc_f <- apply(summed, 2, function(x) max(which(x < expected_errors)))
    
    ## Create the percentile distribution of sequence length that satisfies the threshold
    f_quant <- quantile(trunc_f, probs=c(seq(0,1,0.01)))
    
    ## The same for reverse if its not NULL
    if (!is.null(reverseReads)) {
      fqFile <- reverseReads[x]
      reads <- readFastq(fqFile)
      qual <- as(quality(reads[sample(x = seq(1,length(sread(reads))), size = sample_size, replace = F)]), "matrix")
      qual[is.na(qual)] <- 0
      error <- 10^(-1*qual/10)
      summed <- apply(error, 1, cumsum)
      trunc_r <- apply(summed, 2, function(x) max(which(x < expected_errors)))
      r_quant <- quantile(trunc_r, probs=c(seq(0,1,0.01)))
      
      i <- 1
      
      # Goes through the percentile distribution until the forward length and reverse sums more the amplicon length and the minimum required overlap
      while(f_quant[i] + r_quant[i] < readLen + overlap) {
        i <- i+1
      }
      
      lengths[x,] <- c(f_quant[i], r_quant[i])
      rm(i)
    } else {
      lengths[x,] <- f_quant[1]
    }
  }
  truncLen <- floor(mean(lengths[,1],na.rm=TRUE))
  if (!is.null(reverseReads)) {
    truncLenR <- floor(mean(lengths[,2],na.rm=TRUE))
    return(c(truncLen,truncLenR))
  } else {
    return(truncLen)
  }
}

#!#!#!#!#!#!#!#!#!#!#!#!#!#!#!#!#! WORKFLOW #!#!#!#!#!#!#!#!#!#!#!#!#!#!#!#!#!#!#!#

# if demultiplex is TRUE import and demultiplex data
if (multiplexed == TRUE) {
  barcodes <- samples.info$BARCODES
  sampleNames <- samples.info$NAMES
  
  if (dataType == "Illumina") {
    if (!isPaired) {
      message("reading in data...")
      data <- importIlluminaData(forwardReads, forwardBarcodes, barcodesType, isPaired)
      demultiplex(data, dataDir, barcodesType, barcodes, sampleNames)
    } else {
      dataF <- importIlluminaData(forwardReads, forwardBarcodes, barcodesType, isPaired)
      demultiplex(dataF, dataDir, barcodesType, barcodes, sampleNames, suffix = "_R1_001")
      dataR <- importIlluminaData(reverseReads, reverseBarcodes, barcodesType, isPaired)
      demultiplex(dataR, dataDir, barcodesType, barcodes, sampleNames, suffix = "_R2_001")
    }
    dataDir <- file.path(dataDir, "demux")
  }
}

if (isPaired) {
  fReads <- list.files(dataDir, pattern = "_R1_001.fastq", full.names = TRUE)
  rReads <- list.files(dataDir, pattern = "_R2_001.fastq", full.names = TRUE)
  if (truncLen == 'none') {
    truncLens <- findTruncLen(forwardReads = fReads, reverseReads = rReads, readLen = readLen)
    truncLen <- truncLens[1]
    truncLenR <- truncLens[2]
  }
} else {
  fReads <- list.files(dataDir, pattern = ".fastq", full.names = TRUE)
  if (truncLen == 'none') {
    truncLen <- findTruncLen(forwardReads = fReads, readLen = readLen)
  }
} 


if (!is.null(samples.info)) {
  if ("GROUPS" %in% colnames(samples.info)) {
    groups <- unique(samples.info$GROUPS)
  } else {
    groups <- NULL
  }
} else {
  groups <- NULL
}
message("determining if there are groups...")
#run dada2 in selfConsist mode to build error model
if (is.null(groups)) {
  message("building error model...")
  errFile <- file.path(inputDir, "err.rds")
  asvTable <- buildErrors(dataDir, errFile, dataType, readType, truncLen, truncLenR, trimLeft, trimLeftR)
} else {
  asvTable <- NULL
  for (group in groups) {
    myFiles <- samples.info$NAMES[samples.info$GROUPS == group]
    errFile <- paste0(group, "_err.rds")
    errFile <- file.path(inputDir, errFile)
    if (isPaired) {
      temp <- paste0(myFiles, "_R1_001.fastq")
      temp2 <- paste0(myFiles, "_R2_001.fastq")
      myFiles <- c(temp, temp2)
    } else {
      myFiles <- paste0(myFiles, ".fastq")
    }
    myFiles <- file.path(dataDir, myFiles)
    myTable <- buildErrors(myFiles, errFile, dataType, readType, truncLen, truncLenR, trimLeft, trimLeftR)
    if (is.null(asvTable)) {
      asvTable <- myTable
    } else {
      myTable$features <- rownames(myTable)
      asvTable$features <- rownames(asvTable)
      asvTable <- merge(asvTable, myTable, all = TRUE, by = "features")
      rm(myTable)
      rownames(asvTable) <- asvTable$features
      asvTable$features <- NULL
    }
  }
}
message("writing table...")
write.table(asvTable, file = file.path(dataDir, "filtered/featureTable.tab"), quote=FALSE, sep='\t', col.names = NA)