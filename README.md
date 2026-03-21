# MSX Music Player

MSX용 VGZ/VGM 파일 플레이어. MSX-DOS 실행파일(.COM)과 ROM 카트리지 두 가지 형태로 동작합니다.

## Features

- AY-3-8910 PSG 음악 재생 (VGZ/VGM 포맷)
- MSX-DOS 플레이어 (`MPSPLAY.COM`)
- ROM 카트리지 플레이어 (Konami 매퍼, 128KB)
- 루프 지원
- Windows/Linux/macOS 빌드 지원

## Requirements

- Python 3.x
- `tools/z80asm.exe` (Windows, 동봉) 또는 시스템의 `z80asm`
- openMSX (실행/테스트용)

## Building

```bash
# 전체 빌드 (VGZ 변환 + MPSPLAY.COM 빌드)
mingw32-make

# MSX-DOS 디스크 이미지 생성
mingw32-make msx-disk

# ROM 카트리지 빌드
mingw32-make msx-rom

# VGZ → MPS 변환만 (50Hz MSX의 경우 FPS=50)
mingw32-make convert-msx FPS=60

# 빌드 결과물 삭제
mingw32-make clean
```

## Usage

### MSX-DOS (`MPSPLAY.COM`)

```
MPSPLAY USASMO01.MPS
```

### ROM 카트리지

openMSX로 실행:
```bash
openmsx -machine Panasonic_FS-A1GT -cart build/player.rom
```

숫자 키로 곡 선택, 재생 후 자동으로 메뉴로 복귀.

## File Structure

```
msx-music/
├── msx/
│   ├── player.asm       # MSX-DOS 플레이어 (Z80)
│   └── player_rom.asm   # ROM 카트리지 플레이어 (Z80)
├── tools/
│   ├── z80asm.exe       # Z80 어셈블러 (Windows 바이너리)
│   ├── vgz2mpsg.py      # VGZ → MPS 변환기
│   ├── convert_msx.py   # 배치 변환 (vgz/ → data/)
│   ├── build_msx_rom.py # ROM 이미지 빌드
│   └── make_msx_disk.py # MSX-DOS 디스크 이미지 생성
├── vgz/                 # 소스 VGZ 파일
├── data/                # 변환된 MPS 파일 (빌드 결과물)
├── build/               # 빌드 출력
│   ├── MPSPLAY.COM      # MSX-DOS 플레이어
│   ├── player.rom       # ROM 카트리지
│   └── msx-music.dsk    # MSX-DOS 디스크 이미지
└── Makefile
```

## MPSG Format

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
