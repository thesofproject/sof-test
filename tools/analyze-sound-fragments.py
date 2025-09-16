import sys
from pydub import AudioSegment, silence


def count_sound_fragments(file):
    audio = AudioSegment.from_wav(file)

    audio_fragments = silence.split_on_silence(
        audio,
        min_silence_len=100,
        silence_thresh=audio.dBFS,
        keep_silence=100
    )
    return len(audio_fragments)
    

if __name__ == "__main__":
    if len(sys.argv) != 3:
        print("Wrong nr of arguments! Usage: python3 analyze-sound-fragments.py <path_to_wav_file> <expected_sound_fragments_nr>")
        sys.exit(1)

    filename=sys.argv[1]
    expected_chs_nr=int(sys.argv[2])

    result = count_sound_fragments(filename)
    print(f"Found sound from {result} channels")
    sys.exit(0 if result==expected_chs_nr else 1)
