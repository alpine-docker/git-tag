FROM node:alpine

COPY entrypoint.sh /entrypoint.sh

RUN apk update && apk add bash git curl jq && npm install -g semver

CMD ["/entrypoint.sh"]
