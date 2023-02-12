#!/usr/bin/env bash
http -a admin:350e0bcb-657a-4d54-8c36-82a20747fa68  \
  POST http://10.233.1.2:8081/service/rest/v1/repositories/maven/hosted/ \
  "name=example" \
  "online:=true" \
  "storage[blobStoreName]=default" \
  "storage[writePolicy]=allow_once" \
  "storage[strictContentTypeValidation]:=true" \
  "maven[contentDisposition]=inline" \
  "maven[versionPolicy]=MIXED" \
  "maven[layoutPolicy]=STRICT"
