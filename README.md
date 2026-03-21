# MSX Music Player

MSX용 VGZ/VGM 파일 플레이어. MSX-DOS 실행파일(.COM)과 ROM 카트리지 두 가지 형태로 동작합니다.

## 다운로드

[GitHub Releases](../../releases)에서 최신 빌드를 받을 수 있습니다:

| 파일 | 설명 |
|------|------|
| `msx-music.dsk` | MSX-DOS 부팅 디스크 |
| `player.rom` | ROM 카트리지 이미지 |
| `MENU.COM` | MSX-DOS 대화형 메뉴 플레이어 |
| `MPSPLAY.COM` | MSX-DOS 단일 파일 플레이어 |
| `convert_msx.py` | VGM/VGZ → MPS 변환 스크립트 |

## Features

- AY-3-8910 PSG 음악 재생 (VGZ/VGM 포맷)
- MSX-DOS 메뉴 플레이어 (`MENU.COM`) — a~z 키 선택, 3분 자동전환, 전체 반복
- MSX-DOS 단일 파일 플레이어 (`MPSPLAY.COM`)
- ROM 카트리지 플레이어 (Konami 매퍼, 128KB)
- 루프 지원

## Requirements

- Python 3.x
- `tools/z80asm.exe` (Windows, 동봉) 또는 시스템의 `z80asm`
- openMSX (실행/테스트용)

## Building

```bash
# MSX-DOS 디스크 이미지 생성 (VGZ 변환 + COM 빌드 포함)
make msx-disk

# ROM 카트리지 빌드
make msx-rom

# VGZ → MPS 변환만 (50Hz MSX의 경우 FPS=50)
make convert-msx FPS=60

# 빌드 결과물 삭제
make clean
```

## Usage

### MSX-DOS 디스크 (`msx-music.dsk`)

```bash
openmsx -machine Panasonic_FS-A1GT -diska msx-music.dsk
```

부팅 시 자동으로 메뉴(`MENU.COM`)가 실행됩니다.

**메뉴 조작:**
- `a`~`z` — 곡 선택 및 재생 시작
- 재생 중 아무 키 — 다음 곡으로 건너뜀
- `ESC` — 메뉴로 복귀
- 3분 경과 시 자동으로 다음 곡 재생 (전체 반복)

### ROM 카트리지 (`player.rom`)

```bash
openmsx -machine Panasonic_FS-A1GT -cart player.rom
```

조작 방법은 메뉴와 동일합니다.

### 단일 파일 재생 (`MPSPLAY.COM`)

```
MPSPLAY TITLE.MPS
```

## VGM/VGZ 변환 (`convert_msx.py`)

VGM/VGZ 파일을 MPS 형식으로 변환합니다.

```bash
python convert_msx.py <입력폴더> <출력폴더> [FPS]

# 예시
python convert_msx.py vgz data 60   # 60Hz NTSC
python convert_msx.py vgz data 50   # 50Hz PAL
```

파일명은 곡명 앞 6자(영숫자) + 2자리 인덱스로 생성됩니다 (예: `USASMO01.MPS`).

## File Structure

```
msx-music/
├── msx/
│   ├── player.asm       # MSX-DOS 단일 플레이어 (Z80)
│   ├── menu.asm         # MSX-DOS 메뉴 플레이어 (Z80)
│   └── player_rom.asm   # ROM 카트리지 플레이어 (Z80)
├── tools/
│   ├── z80asm.exe       # Z80 어셈블러 (Windows 바이너리)
│   ├── convert_msx.py   # VGZ → MPS 배치 변환
│   ├── build_msx_rom.py # ROM 이미지 빌드
│   └── make_msx_disk.py # MSX-DOS 디스크 이미지 생성
├── vgz/                 # 소스 VGZ 파일
├── data/                # 변환된 MPS 파일 (빌드 결과물)
├── build/               # 빌드 출력
│   ├── MPSPLAY.COM
│   ├── MENU.COM
│   ├── player.rom
│   └── msx-music.dsk
└── Makefile
```

## MPS Format

MSX-DOS 플레이어용 커스텀 포맷:

```
Header (16 bytes):
  0-3:  Magic "MPSG"
  4-5:  Data length (little-endian)
  6-7:  Loop offset (0 = no loop)
  8-15: Reserved

Data Stream:
  00-0D vv  : PSG 레지스터 쓰기
  80-FD     : 1-126 프레임 대기
  FD        : 루프 마커
  FE        : 곡 끝
  FF ll hh  : 확장 대기 (16-bit 프레임 수)
```

## Credits

- Player by Honux
- Z80 assembler: z80asm 1.8
