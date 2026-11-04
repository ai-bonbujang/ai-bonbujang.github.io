---
layout: page
title: 모아보기
permalink: /series/
description: '"AI 팀원 첫 출근" 시리즈 전체 목록이에요. 자료 정리, 메일, 엑셀, 회의록, 번역까지 업무별 AI 팀원에게 일을 맡기는 법을 한곳에서 볼 수 있어요.'
---

"AI 팀원 첫 출근" 시리즈 전체 목록이에요. 업무 하나에 AI 팀원 한 명씩, 맡길 수 있는 일과 못 맡기는 일, 첫 업무 주는 법, 직접 재 본 전과 후를 적었어요. 내 업무와 가까운 글부터 골라 읽으면 돼요.

{% assign series = site.posts | where_exp: "p", "p.title contains 'AI 팀원 첫 출근'" | sort: "date" %}
{% for p in series %}
- [{{ p.title | remove: 'AI 팀원 첫 출근 ' }}]({{ p.url | relative_url }}){% if p.subtitle %} — {{ p.subtitle }}{% endif %}
{% endfor %}
