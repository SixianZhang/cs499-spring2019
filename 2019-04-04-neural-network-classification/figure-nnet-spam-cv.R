library(ggplot2)
library(data.table)
library(directlabels)
future::plan("multiprocess")

data(spam, package="ElemStatLearn")
head(spam)
head(y.vec <- ifelse(spam$spam=="spam", 1, -1))
table(y.vec)
head(X.mat <- as.matrix(subset(spam, select=-spam)))

is.binary <- all(y.vec %in% c(1, -1))
line.search.factor <- NULL
line.search.factor <- 3
n.folds <- 4
logistic.loss <- function(pred, y){
  log(1+exp(-y * pred))
}
sigmoid <- function(a){
  1/(1+exp(-a))
}
set.seed(2)
(unique.folds <- 1:n.folds)
fold.vec <- sample(rep(unique.folds, l=nrow(X.mat)))
n.hidden.units <- 100 # u
max.iterations <- 1000
OneFold <- function(validation.fold, step.size=1){
  is.train <- fold.vec != validation.fold
  X.train <- X.mat[is.train, ]
  y.train <- y.vec[is.train]
  X.sc <- scale(X.train)
  set.seed(1)
  V <- matrix(rnorm(ncol(X.sc)*n.hidden.units), ncol(X.sc), n.hidden.units)
  w <- rnorm(n.hidden.units)
  iteration.dt.list <- list()
  iteration.vec <- 1:max.iterations
  for(iteration in iteration.vec){
    head(A <- X.sc %*% V) #1
    head(Z <- sigmoid(A)) #2
    head(b <- as.numeric(Z %*% w))
    dw <- if(is.binary){
      -y.train * sigmoid(-y.train * b)
    }else{
      b-y.train
    }
    A.deriv <- Z * (1-Z)
    dv <- dw * A.deriv * matrix(w, nrow(A.deriv), ncol(A.deriv), byrow=TRUE)
    grad.w <- t(Z) %*% dw / nrow(X.sc)
    grad.V <- t(X.sc) %*% dv / nrow(X.sc)
    cost.w.V <- function(w.vec, V.mat){
      b <- sigmoid(X.sc %*% V.mat) %*% w.vec
      mean(logistic.loss(b, y.train))
    }
    cost.step <- function(step){
      cost.w.V(w-step*grad.w, V-step*grad.V)
    }
    if(is.numeric(line.search.factor)){
      while(cost.step(step.bigger <- step.size*line.search.factor) < cost.step(step.size)){
        step.size <- step.bigger
      }
      while(cost.step(step.smaller <- step.size/line.search.factor) < cost.step(step.size)){
        step.size <- step.smaller
      }
    }
    if(FALSE){
      curve(sapply(x, cost.step), 0, 300)
    }
    w <- w - step.size * grad.w
    V <- V - step.size * grad.V
    predict.sc <- function(X.tilde){
      A.mat <- X.tilde %*% V
      sigmoid(A.mat) %*% w
    }
    predict1.orig <- function(X.unsc){
      X.tilde <- scale(
        X.unsc, attr(X.sc, "scaled:center"), attr(X.sc, "scaled:scale"))
      predict.sc(X.tilde)
    }
    V.orig <- V/attr(X.sc, "scaled:scale")
    b.orig <- - t(V/attr(X.sc, "scaled:scale")) %*% attr(X.sc, "scaled:center")
    V.with.intercept <- rbind(intercept=as.numeric(b.orig), V.orig)
    predict2.orig <- function(X.unsc){
      A.mat <- cbind(1, X.unsc) %*% V.with.intercept
      sigmoid(A.mat) %*% w
    }
    rbind(
      as.numeric(head(predict.sc(X.sc))),
      as.numeric(head(predict1.orig(X.train))),
      as.numeric(head(predict2.orig(X.train))))
    ## train/validation error.
    pred.vec <- as.numeric(predict2.orig(X.mat))
    is.error <- ifelse(pred.vec > 0, 1, -1) != y.vec
    log.loss <- logistic.loss(pred.vec, y.vec)
    square.loss <- (y.vec-pred.vec)^2
    iteration.dt.list[[iteration]] <- data.table(
      set=ifelse(is.train, "train", "validation"),
      is.error, square.loss,
      log.loss)[, list(
        iteration,
        validation.fold,
        mean.square.loss=mean(square.loss),
        error.percent=mean(is.error)*100,
        mean.log.loss=mean(log.loss)
      ), by=list(set)]
  }
  do.call(rbind, iteration.dt.list)
}
fold.dt.list <- future.apply::future_lapply(unique.folds, OneFold)
(fold.dt <- do.call(rbind, fold.dt.list))

fold.tall <- melt(
  fold.dt,
  measure.vars=c("error.percent", "mean.log.loss"))
min.tall <- fold.tall[, {
  .SD[which.min(value)]
}, by=list(variable, set, validation.fold)]
set.colors <- c(
  train="black",
  validation="red")
gg <- ggplot()+
  ggtitle(paste(
    "Single layer neural network (57, 100, 1) for binary classification",
    "of spam data, N_train=2300, N_validation=2301, line search", sep="\n"))+
  theme_bw()+
  theme(panel.margin=grid::unit(0, "lines"))+
  scale_color_manual(values=set.colors)+
  facet_grid(variable ~ validation.fold, scales="free", labeller=label_both)+
  geom_line(aes(
    iteration, value, color=set),
    data=fold.tall)+
  scale_shape_manual(values=c(min=1))+
  geom_point(aes(
    iteration, value, color=set, shape=Value),
    size=3,
    data=data.table(Value="min", min.tall))+
  ylab("")+
  scale_x_continuous(limits=c(0, 1400))
dl <- direct.label(gg, "last.polygons")
png("figure-nnet-spam-cv-folds.png", 10, 6, units="in", res=100)
print(dl)
dev.off()

stats.tall <- fold.tall[, list(
  mean=mean(value),
  sd=sd(value)
  ), by=list(variable, set, iteration)]
stats.min <- stats.tall[, {
  .SD[which.min(mean)]
}, by=list(variable, set)]
gg <- ggplot()+
  ggtitle(paste(
    "Single layer neural network (57, 100, 1) for binary classification",
    "of spam data, N_train=2300, N_validation=2301, line search", sep="\n"))+
  theme_bw()+
  theme(panel.margin=grid::unit(0, "lines"))+
  scale_color_manual(values=set.colors)+
  scale_fill_manual(values=set.colors)+
  facet_grid(variable ~ ., scales="free")+
  geom_line(aes(
    iteration, mean, color=set),
    data=stats.tall)+
  geom_ribbon(aes(
    iteration, ymin=mean-sd, ymax=mean+sd, fill=set),
    alpha=0.5,
    data=stats.tall)+
  scale_shape_manual(values=c(min=21))+
  geom_point(aes(
    iteration, mean, color=set, shape=Value),
    fill="white",
    size=3,
    data=data.table(Value="min", stats.min))+
  ylab("")+
  scale_x_continuous(limits=c(0, 1200))
dl <- direct.label(gg, "last.polygons")
png("figure-nnet-spam-cv.png", 6, 6, units="in", res=100)
print(dl)
dev.off()

