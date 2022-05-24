# api-breaker-auto
The APISIX dynamic fuse plugin implemented by Google SRE algorithm.

## steps
1. Download the plugin code and put it in the apisix/plugins directory
2. Configure conf/config-default.yaml

## parameters
- policy: currently only redis;
- Redis related configuration: redis_host, redis_port, redis_database;
- break_response_code: The definition of the HTTP status code returned to the client after the circuit breaker is triggered, the default is 502;
- window: Statistics of the data window on which the fusing algorithm is based, the default is 60s;
- k: The multiplier for triggering the fuse, the smaller the more aggressive, the larger the more conservative, the default is 2;
- unhealthy.http_statuses: upstream service exception status code definition, default {500};

## Google SRE
[Handling Overload](https://sre.google/sre-book/handling-overload/)

## Window data statistics
Redis Sorted Set

***
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