# 이모지 랭커 증류 실험 (반려)

2026-10-04 종료. 결론: **반려.** 로컬 Gemma 4 E4B를 그대로 써도 속도가 충분하고, 증류한 랭커의 품질은 아직 쓸 수준이 아니었다.

## 목표

Gemma 4가 고르는 이모지를 작은 임베딩 랭커로 증류해, 생성형 모델 없이 빠르게 추천한다.

## 구성

- 교사: `google/gemma-4-31B-it-qat-w4a16-ct` (vLLM 배치 32), 카탈로그 `emoji-18.0`
- 학생: `intfloat/multilingual-e5-small` + LoRA. 학습 파라미터 762,942 / 전체 118,416,702
- 원문: 위키백과 en/ja/ko/zh의 제목(heading)과 문장(sentence) 60,000개
- 증류: 40,000개 항목 × 톤 4종(neutral, warm, dry, playful) × 10회 반복 = 1,600,000 슬롯. 빈도로 집계해 가중치 라벨을 만듦
- 분할: train 151,656 / dev 8,344

## 결과 (dev)

| 에폭 | recall@5 | macro top recall@5 |
| --- | --- | --- |
| 1 | 0.520 | 0.295 |
| 4 | 0.553 | 0.395 |
| 8 | **0.560** | **0.404** |

에폭 8 기준 세부 recall@5:

- heading: ko 0.645, en 0.571, ja 0.567, zh 0.553
- sentence: ko 0.608, ja 0.550, zh 0.547, en 0.534

에폭 4 이후로는 0.553에서 0.560으로, 거의 늘지 않았다. 한국어가 가장 높고, 영어 문장이 가장 낮았다.

## 남은 것

- 코드: `experiment/scratch` 브랜치 (`experiments/emoji-ranker/`)
- 에폭 이어 학습 기능과 Gemma 비교 훅: `stash@{0}`
- 체크포인트, 증류 데이터, venv(약 4.4GB)는 삭제했다.
