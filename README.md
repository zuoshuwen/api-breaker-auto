# api-breaker-auto
借鉴 Google SRE 算法实现的 APISIX 动态熔断插件。

## 步骤
1. 下载插件代码，放入 apisix/plugins 目录
2. 配置 conf/config-default.yaml

## 参数
- policy：目前只有 redis；
- redis相关配置：redis_host、redis_port、redis_database；
- break_response_code：触发熔断后返回给客户端的 HTTP 状态码定义，默认 502；
- window：熔断算法依据的数据窗口的统计，默认 60s；
- k：触发熔断的倍值，越小越激进，越大越保守，默认为 2；
- unhealthy.http_statuses：上游服务异常状态码定义，默认 {500}；

## Google SRE
[Handling Overload](https://sre.google/sre-book/handling-overload/)

## 窗口数据统计
Redis 有序集合