---
title: "AnyTLS - sing-box"
source: "https://sing-box.sagernet.org/zh/configuration/inbound/anytls/"
author:
  - "[[nekohasekai]]"
published:
created: 2026-06-04
description: "The universal proxy platform."
tags:
  - "clippings"
---
## AnyTLS

> [!question] 自 sing-box 1.12.0 起
> 

### 结构

```js
{
  "type": "anytls",
  "tag": "anytls-in",

  ... // 监听字段

  "users": [
    {
      "name": "sekai",
      "password": "8JCsPssfgS8tiRwiMlhARg=="
    }
  ],
  "padding_scheme": [],
  "tls": {}
}
```

### 监听字段

参阅 [监听字段](https://sing-box.sagernet.org/zh/configuration/shared/listen/) 。

### 字段

#### users

==必填==

AnyTLS 用户。

#### padding\_scheme

AnyTLS 填充方案行数组。

默认填充方案:

```js
[
  "stop=8",
  "0=30-30",
  "1=100-400",
  "2=400-500,c,500-1000,c,500-1000,c,500-1000,c,500-1000",
  "3=9-9,500-1000",
  "4=500-1000",
  "5=500-1000",
  "6=500-1000",
  "7=500-1000"
]
```

#### tls

TLS 配置, 参阅 [TLS](https://sing-box.sagernet.org/zh/configuration/shared/tls/#%E5%85%A5%E7%AB%99) 。