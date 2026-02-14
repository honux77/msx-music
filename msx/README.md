# MSX-DOS PSG Port (WIP)

이 폴더는 Apple II 버전과 별도로 `MSX-DOS`용 PSG 플레이어를 개발하기 위한 시작점입니다.

## 현재 상태
- `player.asm`: Z80 MSX-DOS `.COM` 플레이어 (`PLAYER <파일명>` 형태)
- `tools/vgz2mpsg.py`: VGZ/VGM -> MPSG 변환기
- `make convert-msx`: `8.3` 규칙 파일명(`*.MPS`)으로 변환

## 빠른 사용
```bash
make convert-msx FPS=60
make msx-player
```

MSX-DOS에서:
```text
PLAYER TITLE.MPS
```

## MPSG 포맷
- 16바이트 헤더
  - `0..3`: `MPSG`
  - `4..5`: 데이터 길이(LE)
  - `6..7`: 루프 오프셋(LE, 0=루프 없음)
  - `8..15`: 예약
- 데이터 스트림
  - `00..0D vv`: PSG 레지스터 쓰기
  - `80..FD`: 1..126 프레임 대기
  - `FF ll hh`: 확장 대기(16비트 프레임)
  - `FE`: 곡 종료
  - `FD`: 루프 시작 마커

## 다음 단계
- 어셈블러 확정(`sjasmplus` 또는 `pasmo`)
- `INCBIN`으로 `.MPS` 포함한 실제 `.COM` 빌드
- BDOS 인자 파싱으로 파일 로드 재생
