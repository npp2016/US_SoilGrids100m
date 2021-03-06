## Functions to prepare 100 m covariates and generate predictions
## Tom.Hengl@isric.org

make_RDS_tiles <- function(i, tile.tbl, in.path="/data/GEOG/NASIS/covs100m", out.path="/data/tt/NASIS/covs100m", mask="/data/GEOG/NASIS/covs100m/COUNTY6.tif", covs.lst, NLCD116.leg, PMTGSS7.leg, DRNGSS7.leg, PVEGKT6.leg, COUNTY6.leg, GESUSG6.leg){
  out.rda <- paste0(out.path, "/T", tile.tbl[i,"ID"], "/T", tile.tbl[i,"ID"], ".rds")
  if(!file.exists(out.rda)){
    m = readGDAL(fname=mask, offset=unlist(tile.tbl[i,c("offset.y","offset.x")]), region.dim=unlist(tile.tbl[i,c("region.dim.y","region.dim.x")]), output.dim=unlist(tile.tbl[i,c("region.dim.y","region.dim.x")]), silent = TRUE)
    names(m)[1] = "COUNTY6"
    m = as(m, "SpatialPixelsDataFrame")
    x = spTransform(m, CRS("+proj=longlat +datum=WGS84"))
    m$LONWGS84 <- x@coords[,1]
    m$LATWGS84 <- x@coords[,2]
    for(j in 1:length(covs.lst)){
      m@data[,covs.lst[j]] <- signif(readGDAL(paste0(in.path, "/", covs.lst[j], ".tif"), offset=unlist(tile.tbl[i,c("offset.y","offset.x")]), region.dim=unlist(tile.tbl[i,c("region.dim.y","region.dim.x")]), output.dim=unlist(tile.tbl[i,c("region.dim.y","region.dim.x")]), silent = TRUE)$band1[m@grid.index], 4)
    }
    m$ID = m@grid.index
    ## factors:
    m@data[,"COUNTY6"] = plyr::join(data.frame(X=m$COUNTY6), COUNTY6.leg, type="left")$NAMES
    m@data[,"PMTGSS7"] = plyr::join(data.frame(VALUE=m$PMTGSS7), PMTGSS7.leg, type="left")$pmaterial_class_f
    m@data[,"DRNGSS7"] = plyr::join(data.frame(Value=m$DRNGSS7), DRNGSS7.leg, type="left")$aggregate_class
    m@data[,"NLCD116"] = plyr::join(data.frame(Value=m$NLCD116), NLCD116.leg, type="left")$LC_class
    m@data[,"PVEGKT6"] = plyr::join(data.frame(X=m$PVEGKT6), PVEGKT6.leg, type="left")$NAMES
    m@data[,"GESUSG6.f"] = plyr::join(data.frame(X=m$GESUSG6), GESUSG6.leg, type="left")$NAMES
    ## Convert geology to indicators
    i.df = data.frame(model.matrix( ~ GESUSG6.f - 1, data=m@data))
    names(i.df) = make.names(names(i.df))
    i.df <- i.df[match(rownames(m@data),rownames(i.df)),]
    i.df$ID = m$ID
    m@data = plyr::join_all(list(m@data, i.df), by="ID", match="first")
    ## systematically fill in missing values (only possible for numeric vars):
    sel.mis = sapply(m@data, function(x){sum(is.na(x))>0})
    if(sum(sel.mis)>0){
      for(j in which(sel.mis)){
        if(!is.factor(m@data[,j])){
          if(length(grep(pattern="GESUSG6", names(m)[j]))>0){ 
            repn = 0 
          } else {
            repn = quantile(m@data[,j], probs=.5, na.rm=TRUE)
          }
          m@data[,j] = ifelse(is.na(m@data[,j]), repn, m@data[,j])
        }
      }
    }
    ## Fill in missing pixels in: Parent material
    pm.out = paste0(out.path, "/T", tile.tbl[i,"ID"], "/PMTGSS7_predicted_", tile.tbl[i,"ID"], ".tif")
    if(!file.exists(pm.out)){
      rf.pm = readRDS("/data/USA48/RF_parent_material.rds")
      out = predict(rf.pm, m@data[,rf.pm$forest$independent.variable.names])
      if(length(out$predictions)==nrow(m)){
        m$PMTGSS7.f = ifelse(paste(out$predictions)=="NA", "NULL", paste(out$predictions))
        m$PMTGSS7 = ifelse(is.na(m$PMTGSS7), paste(m$PMTGSS7.f), paste(m$PMTGSS7))
        g = m["PMTGSS7"]
        g$INT = plyr::join(data.frame(pmaterial_class_f=g$PMTGSS7), PMTGSS7.leg, type="left", match="first")$VALUE
        writeGDAL(g["INT"], pm.out, options="COMPRESS=DEFLATE")
      }
    } else {
      v = readGDAL(pm.out)$band1[m@grid.index]
      m$PMTGSS7.f = plyr::join(data.frame(VALUE=v), PMTGSS7.leg, type="left", match="first")$pmaterial_class_f
      m$PMTGSS7 = ifelse(is.na(m$PMTGSS7), paste(m$PMTGSS7.f), paste(m$PMTGSS7))
    }
    ## Fill in missing pixels in: Drainage class
    dr.out = paste0(out.path, "/T", tile.tbl[i,"ID"], "/DRNGSS7_predicted_", tile.tbl[i,"ID"], ".tif")
    if(!file.exists(dr.out)){
      rf.dr = readRDS("/data/USA48/RF_drainage_class.rds")
      out = predict(rf.dr, m@data[,rf.pm$forest$independent.variable.names])
      if(length(out$predictions)==nrow(m)){
        m$DRNGSS7.f = ifelse(paste(out$predictions)=="NA", "NULL", paste(out$predictions))
        m$DRNGSS7 = ifelse(is.na(m$DRNGSS7), paste(m$DRNGSS7.f), paste(m$DRNGSS7))
        g = m["DRNGSS7"]
        g$INT = plyr::join(data.frame(aggregate_class=g$DRNGSS7), DRNGSS7.leg, type="left", match="first")$Agg_Value
        writeGDAL(g["INT"], paste0(out.path, "/T", tile.tbl[i,"ID"], "/DRNGSS7_predicted_", tile.tbl[i,"ID"], ".tif"), options="COMPRESS=DEFLATE")
      }
    } else {
      v = readGDAL(dr.out)$band1[m@grid.index]
      m$DRNGSS7.f = plyr::join(data.frame(Value=v), DRNGSS7.leg, type="left", match="first")$aggregate_class
      m$DRNGSS7 = ifelse(is.na(m$DRNGSS7), paste(m$DRNGSS7.f), paste(m$DRNGSS7))
    }
    ## Save output:
    saveRDS(m, file=out.rda, compress=TRUE)
    gc(); gc()
  }
}


extract.tiled <- function(x, tile.pol, path="/data/tt/NASIS/covs100m", ID="ID", cpus=48){
  x$row.index <- 1:nrow(x)
  ov.c <- over(spTransform(x, CRS(proj4string(tile.pol))), tile.pol)
  ov.t <- which(!is.na(ov.c[,ID]))
  ## for each point get the tile name:
  ov.c <- data.frame(ID=ov.c[ov.t,ID], row.index=ov.t)
  tiles.lst <- basename(dirname(list.files(path=path, pattern=glob2rx("*.rds$"), recursive=TRUE)))
  ov.c <- ov.c[ov.c[,ID] %in% sapply(tiles.lst, function(i){strsplit(i, "T")[[1]][2]}),]
  tiles <- levels(as.factor(paste(ov.c[,ID]))) 
  cov.c <- as.list(tiles)
  names(cov.c) <- tiles
  ## extract using snowfall
  sfInit(parallel=TRUE, cpus=cpus)
  sfExport("x", "path", "ov.c", "ID", "cov.c", ".extract.tile", "tile.pol")
  sfLibrary(raster)
  sfLibrary(rgdal)
  ov.lst <- sfLapply(1:length(cov.c), function(i){try(.extract.tile(i, x=x, ID=ID, path=path, ov.c=ov.c, cov.c=cov.c, tile.pol=tile.pol), silent = TRUE)}) 
  snowfall::sfStop()
  ## bind together:
  out <- dplyr::bind_rows(ov.lst)
  out <- plyr::join(x@data, as.data.frame(out), type="left", by="row.index")
  return(out)
}

.extract.tile <- function(i, x, ID, path, ov.c, cov.c, tile.pol){
  row.index <- ov.c$row.index[ov.c[,ID]==names(cov.c)[i]]
  pnts <- x[row.index,]
  pnts <- spTransform(pnts, CRS(proj4string(tile.pol)))
  m <- readRDS(paste0(path, "/T", names(cov.c)[i], "/T", names(cov.c)[i], ".rds"))
  out <- sp::over(y=m, x=pnts)
  out$band1 <- NULL
  out$row.index <- row.index
  xy <- data.frame(pnts@coords)
  names(xy) <- c("X","Y")
  out <- cbind(out, xy)
  return(out)
}

## make prediction locations for all factor / numeric variables
make_newdata <- function(i, in.path="/data/tt/NASIS/covs100m", PMTGSS7.leg, DRNGSS7.leg, independent.variable.names, mean.val){
  rds.file = paste0(in.path, "/T", i, "/T", i, ".rds")
  rdsc.file = paste0(in.path, "/T", i, "/cT", i, ".rds")
  if(!file.exists(rdsc.file)){
    m <- readRDS(rds.file)
    m$PMTGSS7 = factor(m$PMTGSS7, levels=unique(PMTGSS7.leg$pmaterial_class_f))
    m$DRNGSS7 = factor(m$DRNGSS7, levels=unique(DRNGSS7.leg$aggregate_class))
    ## mask out pixels of interest:
    #sel.pix = !(m$LNDCOV6=="Ocean"|m$LNDCOV6=="Open Water"|m$LNDCOV6=="Mexico or Russia")
    sel.pix = !(m$NLCD116=="Perrenial Ice"|m$NLCD116=="Open Water"|m$NLCD116=="Developed High Intensity"|is.na(m$NLCD116))
    m = m[sel.pix,]
    ## Convert factors to indicators:
    m.PVEGKT6 = data.frame(model.matrix(~PVEGKT6-1, m@data))
    m.PVEGKT6 <- m.PVEGKT6[match(rownames(m@data),rownames(m.PVEGKT6)),]
    m.PVEGKT6$ID = m$ID
    m.NLCD116 = data.frame(model.matrix(~NLCD116-1, m@data))
    m.NLCD116 <- m.NLCD116[match(rownames(m@data),rownames(m.NLCD116)),]
    m.NLCD116$ID = m$ID
    m.PMTGSS7 = data.frame(model.matrix(~PMTGSS7-1, m@data))
    m.PMTGSS7 <- m.PMTGSS7[match(rownames(m@data),rownames(m.PMTGSS7)),]
    m.PMTGSS7$ID = m$ID
    m.DRNGSS7 = data.frame(model.matrix(~DRNGSS7-1, m@data))
    m.DRNGSS7 <- m.DRNGSS7[match(rownames(m@data),rownames(m.DRNGSS7)),]
    m.DRNGSS7$ID = m$ID
    m@data = plyr::join_all(list(m@data, m.PVEGKT6, m.NLCD116, m.PMTGSS7, m.DRNGSS7), by="ID", match="first")[,independent.variable.names]
    ## systematically fill in missing values (only possible for numeric vars):
    sel.mis = sapply(m@data, function(x){sum(is.na(x))>0})
    if(sum(sel.mis)>0){
      x = which(sel.mis)
      xn = attr(x, "names")
      for(j in 1:length(x)){
        if(!is.factor(m@data[,x[j]])){
          if(length(grep(pattern="PVEGKT6", names(m)[x[j]]))>0 | length(grep(pattern="NLCD116", names(m)[x[j]]))>0){ 
            repn = 0 
          } else {
            if(sum(is.na(m@data[,x[j]]))<length(m)){
              repn = quantile(m@data[,x[j]], probs=.5, na.rm=TRUE)
            } else {
              repn = mean.val[[xn[j]]]
            }
          }
          m@data[,x[j]] = ifelse(is.na(m@data[,x[j]]), repn, m@data[,x[j]])
        }
      }
    }
    m = m[complete.cases(m@data),]
    saveRDS(m, rdsc.file)
  }
}

## Predict classes per tile (fully parallelized):
predict_factor_tile <- function(i, mRF, varn, levs, in.path="/data/tt/NASIS/covs100m", out.path="/data/NASIS/predicted100m", mc.cores=1){
  gc(); gc()
  out.c <- paste0(out.path, "/T", i, "/", varn, "_", levs, "_T", i, ".tif")
  if(any(!file.exists(out.c))){
    if(mc.cores==1){
      m <- readRDS(paste0(in.path, "/T", i, "/cT", i, ".rds"))
    } else {
      m <- readRDS.gz(paste0(in.path, "/T", i, "/cT", i, ".rds"), threads=mc.cores)
    }
    m@data = data.frame(round(predict(mRF, m@data, probability=TRUE)$predictions*100))
    levs.n = names(m)
    ## write to Geotif:
    if(mc.cores==1){
      x = lapply(1:ncol(m), function(x){writeGDAL(m[x], paste0(out.path, "/T", i, "/", varn, "_", names(m)[x], "_T", i, ".tif"), type="Byte", mvFlag=255, options="COMPRESS=DEFLATE")})
    } else {
      x = parallel::mclapply(1:ncol(m), function(x){writeGDAL(m[x], paste0(out.path, "/T", i, "/", varn, "_", names(m)[x], "_T", i, ".tif"), type="Byte", mvFlag=255, options="COMPRESS=DEFLATE")}, mc.cores=mc.cores)
    }
    ## most probable class:
    m$cl <- apply(m@data,1,which.max)
    writeGDAL(m["cl"], paste0(out.path, "/T", i, "/", varn, "_T", i, ".tif"), type="Int16", mvFlag=32767, options="COMPRESS=DEFLATE")
    gc(); gc()
  }
}

split_predict_factor_tile <- function(i, gm, in.path, out.path, split_no, varn){
  if(dir.exists(out.path)){
    rds.out = paste0(out.path, "/T", i, "/", varn,"_T", i, "_rf", split_no, ".rds")
    if(any(c(!file.exists(rds.out),file.size(rds.out)==0))){
      m <- readRDS(paste0(in.path, "/T", i, "/cT", i, ".rds"))
      ## round up numbers otherwise too large objects
      x = round(predict(gm, m@data, probability=TRUE, na.action = na.pass)$predictions*100)
      saveRDS(x, file=rds.out)
      gc(); gc()
    } 
  }
}

## simple ranger predict function:
sum_predict_factor_tile <- function(i, varn, levs, in.path="/data/tt/NASIS/covs100m", out.path="/data/NASIS/predicted100m", num_splits){
  out.c <- paste0(out.path, "/T", i, "/", varn, "_", levs, "_T", i, ".tif")
  if(any(!file.exists(out.c))){
    ## load all objects:
    m <- readRDS(paste0(in.path, "/T", i, "/cT", i, ".rds"))
    if(nrow(m@data)>1){
      rf.ls = paste0(out.path, "/T", i, "/", varn,"_T", i, "_rf", 1:num_splits, ".rds")
      probs <- lapply(rf.ls, readRDS)
      probs <- data.frame(Reduce("+", probs) / num_splits)
      ## Standardize values so they sums up to 100:
      rs <- rowSums(probs, na.rm=TRUE)
      m@data <- data.frame(lapply(probs, function(i){i/rs}))
      ## Write GeoTiffs:
      if(sum(rs,na.rm=TRUE)>0&length(rs)>0){
        tax <- names(m)
        for(j in 1:ncol(m)){
          out <- paste0(out.path, "/T", i, "/", varn, "_", tax[j], "_T", i, ".tif")
          if(!file.exists(out)){
            m$v <- round(m@data[,j]*100)
            writeGDAL(m["v"], out, type="Byte", mvFlag=255, options="COMPRESS=DEFLATE")
          }
        }
      }
      ## most probable class
      m$cl <- apply(m@data,1,which.max)
      writeGDAL(m["cl"], paste0(out.path, "/T", i, "/", varn, "_T", i, ".tif"), type="Int16", mvFlag=32767, options="COMPRESS=DEFLATE")
      unlink(rf.ls)
    }
  }
}

## Create mosaics:
mosaic_tiles_NASIS <- function(j, in.path, varn, latlon=FALSE, tr=0.002083333, r="bilinear", ot="Byte", dstnodata=255, out.path="/data/GEOG/NASIS/predicted100m/"){
  out.tif <- paste0(out.path, varn, "_", j, '_100m.tif')
  if(!file.exists(out.tif)){
    tmp.lst <- list.files(path=in.path, pattern=glob2rx(paste0(varn, "_", j, "_*_*.tif$")), full.names=TRUE, recursive=TRUE)
    out.tmp <- tempfile(fileext = ".txt")
    vrt.tmp <- tempfile(fileext = ".vrt")
    cat(tmp.lst, sep="\n", file=out.tmp)
    system(paste0(gdalbuildvrt, ' -input_file_list ', out.tmp, ' ', vrt.tmp))
    if(latlon==TRUE){
      system(paste0(gdalwarp, ' ', vrt.tmp, ' ', out.tif, ' -t_srs \"+proj=longlat +datum=WGS84\" -r \"', r,'\" -ot \"', ot, '\" -dstnodata \"',  dstnodata, '\" -tr ', tr, ' ', tr, ' -co \"BIGTIFF=YES\" -wm 2000 -co \"COMPRESS=DEFLATE\"'))
    } else {
      system(paste0(gdalwarp, ' ', vrt.tmp, ' ', out.tif, ' -ot \"', ot, '\" -dstnodata \"',  dstnodata, '\" -co \"BIGTIFF=YES\" -wm 2000 -co \"COMPRESS=DEFLATE\"'))
    }
  }
}

## Create mosaics:
mosaic_tiles_100m <- function(j, in.path, varn, r="bilinear", ot="Byte", dstnodata=255, out.path="/data/GEOG/NASIS/predicted100m/", te){
  out.tif <- paste0(out.path, varn, "_", j, "_100m.tif")
  if(!file.exists(out.tif)){
    if(j=="M"){
      tmp.lst <- list.files(path=in.path, pattern=glob2rx(paste0("^",varn, "_T\\d*.tif")), full.names=TRUE, recursive=TRUE) 
    } else {
      tmp.lst <- list.files(path=in.path, pattern=glob2rx(paste0("^",varn, "_", j, "_T*.tif$")), full.names=TRUE, recursive=TRUE)
    }
    out.tmp <- tempfile(fileext = ".txt")
    vrt.tmp <- tempfile(fileext = ".vrt")
    cat(tmp.lst, sep="\n", file=out.tmp)
    system(paste0(gdalbuildvrt, ' -input_file_list ', out.tmp, ' ', vrt.tmp))
    system(paste0(gdalwarp, ' ', vrt.tmp, ' ', out.tif, ' -ot \"', ot, '\" -dstnodata \"',  dstnodata, '\" -co \"BIGTIFF=YES\" -wm 2000 -co \"COMPRESS=DEFLATE\" -tr 100 100 -r \"', r, '\" -te ', te))
  }
}

missing.tiles <- function(varn, pr.dirs){
  dir.lst <- list.files(path="/data/tt/NASIS/predicted100m", pattern=glob2rx(paste0("^", varn, "*.tif")), full.names=TRUE, recursive=TRUE)
  out.lst <- pr.dirs[which(!pr.dirs %in% basename(dirname(dir.lst)))]
  return(out.lst)
}
