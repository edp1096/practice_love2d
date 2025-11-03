# 📚 Documentation

프로젝트 문서 모음

---

## 📋 문서 목록

### 🗂️ **MEMO.md** - 프로젝트 구조 참조
- 전체 폴더/파일 구조
- 파일 개수 및 라인 수 통계
- 아키텍처 패턴 설명
- 플랫폼별 차이점
- 최근 리팩토링 내역

**대상:** 개발자, 코드베이스 전체 파악이 필요한 경우

---

### 🎵 **BGM_GUIDE.md** - 배경음악(BGM) 시스템 가이드
- BGM 추가 방법 (자동/수동)
- 맵 속성을 통한 BGM 지정
- BGM 전환 동작 설명
- Intro/Ending 특수 BGM
- 실전 예제 및 디버깅

**대상:** 맵 제작자, BGM 추가/변경이 필요한 경우

---

### 💊 **HEALTH_RECOVERY_README.md** - 체력 회복 시스템
- Healing Point 시스템 설명
- 맵에 Healing Point 추가하는 방법
- 설정 옵션 (회복량, 쿨다운 등)

**대상:** 맵 디자이너, 체력 회복 지점 추가가 필요한 경우

---

### 📖 **SUMMARY.md** - 기능 요약
- 주요 기능 목록
- 시스템별 간단 설명

**대상:** 프로젝트 개요를 빠르게 파악하고 싶은 경우

---

### 📝 **README_FINAL.md** - 기타 문서
- 레거시 문서 (구체적 내용 확인 필요)

---

## 🔗 프로젝트 메인 문서

### **../CLAUDE.md** - 개발자 가이드 (메인 문서)
프로젝트 루트에 위치한 메인 개발 문서:
- 프로젝트 개요
- 코어 아키텍처
- 개발 워크플로우
- 코드 스타일 가이드
- 게임 모드 차이 (Topdown vs Platformer)
- 공통 문제 해결 (Common Pitfalls)

**대상:** Claude Code (AI 어시스턴트), 신규 개발자

---

## 📁 문서 구조

```
docs/
├── README.md                    (이 파일)
├── MEMO.md                      프로젝트 구조 참조
├── BGM_GUIDE.md                 BGM 시스템 가이드
├── HEALTH_RECOVERY_README.md    체력 회복 시스템
├── SUMMARY.md                   기능 요약
└── README_FINAL.md              레거시 문서

../CLAUDE.md                     메인 개발자 가이드 (루트)
```

---

## 🎯 문서 찾기 가이드

**Q: 프로젝트 전체 구조가 궁금해요**
→ `MEMO.md` 참조

**Q: BGM을 추가하거나 변경하고 싶어요**
→ `BGM_GUIDE.md` 참조

**Q: 새로운 맵에 체력 회복 지점을 추가하고 싶어요**
→ `HEALTH_RECOVERY_README.md` 참조

**Q: 코드를 수정하고 싶은데 어떻게 시작해야 하나요?**
→ `../CLAUDE.md` 참조

**Q: 입력 시스템을 수정하고 싶어요**
→ `../CLAUDE.md` → "Input System" 섹션

**Q: 새로운 적(Enemy)을 추가하고 싶어요**
→ `../CLAUDE.md` → "Adding a New Enemy Type" 섹션

---

**Last Updated:** 2025-11-03
