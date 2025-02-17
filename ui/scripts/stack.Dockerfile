#
# GO Build
#
FROM golang:1.15 AS build-go

ARG chainnet

ENV GOBIN=/go/bin
ENV GOPATH=/go
ENV CGO_ENABLED=0
ENV GOOS=linux

# Empty dir for the db data
RUN mkdir /data

WORKDIR /sif

COPY go.mod go.sum ./
RUN go mod download
RUN go get github.com/cosmos/cosmos-sdk/cosmovisor/cmd/cosmovisor

# Probably dont need all of these...
COPY ./api ./api
COPY ./app ./app
COPY ./cmd ./cmd
COPY ./deploy ./deploy
COPY ./log ./log
COPY ./scripts ./scripts
COPY ./simapp ./simapp
COPY ./test ./test
COPY ./tools ./tools
COPY ./x ./x
COPY ./.gitignore ./.gitignore
COPY ./.golangci.yml ./.golangci.yml
COPY ./config.yml ./config.yml
COPY ./Makefile ./Makefile
COPY ./Rakefile ./Rakefile
COPY ./setup.sh ./setup.sh
COPY ./version ./version

RUN make install


#
# Runtime
#
FROM node:14.11.0

EXPOSE 1317
EXPOSE 7545
EXPOSE 5000
EXPOSE 26656
EXPOSE 26657

RUN apt-get update && apt-get -y install curl jq

# Copy the compiled binaires over.
COPY --from=build-go /go/bin/ebrelayer /usr/bin/ebrelayer
COPY --from=build-go /go/bin/cosmovisor /usr/bin/cosmovisor
COPY --from=build-go /go/bin/sifnoded /usr/bin/sifnoded
COPY --from=build-go /go/bin/sifnodecli /usr/bin/sifnodecli
COPY --from=build-go /go/bin/sifgen /usr/bin/sifgen

# Required for ebrelayer
COPY --from=build-go /sif/cmd/ebrelayer /sif/cmd/ebrelayer

WORKDIR /sif/ui

COPY ./ui/package.json ./package.json
COPY ./ui/yarn.lock ./yarn.lock
COPY ./ui/core/package.json ./core/package.json
COPY ./ui/core/yarn.lock ./core/yarn.lock
COPY ./ui/chains/eth/package.json ./chains/eth/package.json
COPY ./ui/chains/eth/yarn.lock ./chains/eth/yarn.lock
COPY ./smart-contracts/package.json ../smart-contracts/package.json
COPY ./smart-contracts/yarn.lock ../smart-contracts/yarn.lock

RUN yarn install --frozen-lockfile --silent
RUN cd ./chains/eth && yarn install --frozen-lockfile --silent
RUN cd ../smart-contracts && yarn install --frozen-lockfile --silent

COPY ./ui/chains ./chains
COPY ./ui/core/ ./core
COPY ./smart-contracts ../smart-contracts

RUN yarn chain:peggy:build && yarn chain:eth:build

CMD yarn concurrently -k -r -s first "yarn chain:eth:revert" "yarn wait-on tcp:localhost:7545 && yarn chain:sif:revert" "yarn wait-on http-get://localhost:1317/node_info tcp:localhost:7545 && yarn chain:peggy:revert"