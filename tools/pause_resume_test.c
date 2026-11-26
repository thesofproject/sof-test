#include <stdio.h>
#include <stdlib.h>
#include <alsa/asoundlib.h>
#include <unistd.h>
#include <pthread.h>
#include <stdbool.h>

// This program requires ALSA library and a Linux environment with ALSA support.
// sudo apt install libasound2-dev
// To compile: gcc -o pcm_pause pause_test.c -lasound
// To run: ./pcm_pause [pause_count] or ./pcm_pause [pause_count] [playback_device_id] [capture_device_id]
// When the playback_device_id and capture_device_id are provided, it will run the pause/resume test only for that combination.
// Otherwise, the test runs the test for all combinations of playback and capture devices found on the system.
// Deep buffer devices are skipped at the moment.

#define BUFFER_SIZE 4096
#define MAX_PCMS_PLAYBACK 10
#define MAX_PCMS_CAPTURE 10
#define MAX_DEVICE_NAME_LENGTH 32

snd_pcm_t *playback_handle, *capture_handle;
char playback_devices[MAX_PCMS_PLAYBACK][MAX_DEVICE_NAME_LENGTH];
char capture_devices[MAX_PCMS_CAPTURE][MAX_DEVICE_NAME_LENGTH];
char buffer[BUFFER_SIZE] = {0};       // Buffer to simulate playback
char capture_buffer[BUFFER_SIZE] = {0}; // Buffer to store captured data
bool stop_threads = false;           // Flag to signal threads to stop
int pause_count = 20;
int num_playback_devices = 0;
int num_capture_devices = 0;
int playback_framesize = 0;
int capture_framesize = 0 ;

void list_pcm_devices() {
	int card = -1; // Start with the first card
	snd_ctl_t *ctl;
	snd_ctl_card_info_t *card_info;
	snd_pcm_info_t *pcm_info;

	snd_ctl_card_info_malloc(&card_info);
	snd_pcm_info_malloc(&pcm_info);

	while (snd_card_next(&card) >= 0 && card >= 0) {
		char card_name[32];
        	snprintf(card_name, sizeof(card_name), "hw:%d", card);

		if (snd_ctl_open(&ctl, card_name, 0) < 0) {
			fprintf(stderr, "Cannot open control for card %d\n", card);
			continue;
		}

        if (snd_ctl_card_info(ctl, card_info) < 0) {
		fprintf(stderr, "Cannot get card info for card %d\n", card);
		snd_ctl_close(ctl);
		continue;
        }

        // if card name doesnt contain "sof", skip it
	if (strstr(snd_ctl_card_info_get_name(card_info), "sof") == NULL) {
		snd_ctl_close(ctl);
		continue;
	}

	fprintf(stdout, "Card %d: %s\n", card, snd_ctl_card_info_get_name(card_info));

	int device = -1;
	while (snd_ctl_pcm_next_device(ctl, &device) >= 0 && device >= 0) {
		snd_pcm_info_set_device(pcm_info, device);
		snd_pcm_info_set_subdevice(pcm_info, 0);
		snd_pcm_info_set_stream(pcm_info, SND_PCM_STREAM_PLAYBACK);

		// add to playback devices list
		if (snd_ctl_pcm_info(ctl, pcm_info) >= 0 && num_playback_devices < MAX_PCMS_PLAYBACK) {
			// Skip deep buffer device
			if(device != 31)
				snprintf(playback_devices[num_playback_devices++], MAX_DEVICE_NAME_LENGTH, "hw:%d,%d", card, device);
		}

		snd_pcm_info_set_stream(pcm_info, SND_PCM_STREAM_CAPTURE);
		// add to capture devices list
		if (snd_ctl_pcm_info(ctl, pcm_info) >= 0 && num_capture_devices < MAX_PCMS_CAPTURE)
			snprintf(capture_devices[num_capture_devices++], MAX_DEVICE_NAME_LENGTH, "hw:%d,%d", card, device);
            }
        }

        snd_ctl_close(ctl);

	snd_ctl_card_info_free(card_info);
	snd_pcm_info_free(pcm_info);

	// print all playback devices
	fprintf(stdout, "Available Playback Devices:\n");
	for (int i = 0; i < num_playback_devices; i++)
        	fprintf(stdout, "  %s\n", playback_devices[i]);

	// print all capture devices
	fprintf(stdout, "Available Capture Devices:\n");
	for (int i = 0; i < num_capture_devices; i++)
		fprintf(stdout, "  %s\n", capture_devices[i]);
}

void cleanup_pcm_handles() {
	if (playback_handle) {
		snd_pcm_close(playback_handle);
		playback_handle = NULL;
	}
	if (capture_handle) {
		snd_pcm_close(capture_handle);
		capture_handle = NULL;
	}
}

void *playback_thread(void *arg) {
	while (!stop_threads) {
		int err = snd_pcm_writei(playback_handle, buffer, playback_framesize);
		if (err < 0) {
			fprintf(stderr, "Error writing to playback device: %s\n", snd_strerror(err));
			break;
		}
		// calculate wait time based on the period size and sample rate
		
		usleep((playback_framesize / 48000) * 1000000); // Convert to microseconds
    	}
	return NULL;
}

void *capture_thread(void *arg) {
	while (!stop_threads) {
		int err = snd_pcm_readi(capture_handle, capture_buffer, capture_framesize);
		if (err < 0) {
			fprintf(stderr, "Error reading from capture device: %s\n", snd_strerror(err));
			cleanup_pcm_handles();
			break;
		}
		usleep((capture_framesize / 48000) * 1000000); // Convert to microseconds
	}
	return NULL;
}

int run_pause_resume_test(char *playback_device, char *capture_device) {
	snd_pcm_hw_params_t *playback_params_1, *capture_params;
	int err, i;

	// Open first playback PCM device
   	err = snd_pcm_open(&playback_handle, playback_device, SND_PCM_STREAM_PLAYBACK, 0);
	if (err < 0) {
		fprintf(stderr, "Error opening playback device %s: %s\n", playback_device, snd_strerror(err));
		return 1;
	}
	printf("Playback device %s opened successfully.\n", playback_device);

	// Open capture PCM device
	err = snd_pcm_open(&capture_handle, capture_device, SND_PCM_STREAM_CAPTURE, 0);
	if (err < 0) {
		fprintf(stderr, "Error opening capture device %s: %s\n", capture_device, snd_strerror(err));
		snd_pcm_close(playback_handle);
		return 1;
	}
	printf("Capture device %s opened successfully.\n", capture_device);

	// Configure first playback PCM device
	snd_pcm_hw_params_malloc(&playback_params_1);
	snd_pcm_hw_params_any(playback_handle, playback_params_1);
	snd_pcm_hw_params_set_access(playback_handle, playback_params_1, SND_PCM_ACCESS_RW_INTERLEAVED);
	//TODO: check if either 16-bit/2ch is supported for playback
	snd_pcm_hw_params_set_format(playback_handle, playback_params_1, SND_PCM_FORMAT_S16_LE);
	snd_pcm_hw_params_set_channels(playback_handle, playback_params_1, 2);
	snd_pcm_hw_params_set_rate(playback_handle, playback_params_1, 48000, 0);
	playback_framesize = BUFFER_SIZE / (2 * 4); // 2 channels, 4 bytes per sample

	// Set period size for playback
	err = snd_pcm_hw_params_set_period_size(playback_handle, playback_params_1, playback_framesize, 0);
	if (err < 0) {
	    fprintf(stderr, "Error setting period size for playback device %s: %s\n", playback_device, snd_strerror(err));
	    snd_pcm_hw_params_free(playback_params_1);
	    snd_pcm_close(playback_handle);
	    snd_pcm_close(capture_handle);
	    return 1;
	}
	snd_pcm_hw_params(playback_handle, playback_params_1);
	snd_pcm_hw_params_free(playback_params_1);

	// Configure capture PCM device
	snd_pcm_hw_params_malloc(&capture_params);
	snd_pcm_hw_params_any(capture_handle, capture_params);
	snd_pcm_hw_params_set_access(capture_handle, capture_params, SND_PCM_ACCESS_RW_INTERLEAVED);

	int capture_channels = 2;
	int capture_sample_bytes = 2;
	/* check if either 16-bit or 32-bit format is supported for capture */
	if (snd_pcm_hw_params_test_format(capture_handle, capture_params, SND_PCM_FORMAT_S16_LE) == 0) {
		snd_pcm_hw_params_set_format(capture_handle, capture_params, SND_PCM_FORMAT_S16_LE);
	}else if (snd_pcm_hw_params_test_format(capture_handle, capture_params, SND_PCM_FORMAT_S32_LE) == 0) {
		snd_pcm_hw_params_set_format(capture_handle, capture_params, SND_PCM_FORMAT_S32_LE);
		capture_sample_bytes = 4; // 32-bit format
	} else {
		fprintf(stderr, "Unsupported format for capture device %s\n", capture_device);
		snd_pcm_close(playback_handle);
		snd_pcm_close(capture_handle);
		return 1;
	}

	/* check if either 2 or 4 channels are supported for capture */
	if (snd_pcm_hw_params_test_channels(capture_handle, capture_params, 2) == 0) {
		snd_pcm_hw_params_set_channels(capture_handle, capture_params, 2);
	} else if (snd_pcm_hw_params_test_channels(capture_handle, capture_params, 4) == 0) {
		snd_pcm_hw_params_set_channels(capture_handle, capture_params, 4);
		capture_channels = 4;
	} else {
		fprintf(stderr, "Unsupported number of channels for capture device %s\n",
			capture_device);
		snd_pcm_close(playback_handle);
		snd_pcm_close(capture_handle);
		return 1;
	}
	capture_framesize = BUFFER_SIZE / (capture_channels * capture_sample_bytes);

	snd_pcm_hw_params_set_rate(capture_handle, capture_params, 48000, 0);

	// Set period size for capture
	err = snd_pcm_hw_params_set_period_size(capture_handle, capture_params,
						capture_framesize, 0);
	if (err < 0) {
		fprintf(stderr, "Error setting period size for capture device %s: %s\n",
			capture_device, snd_strerror(err));
		snd_pcm_close(playback_handle);
		snd_pcm_close(capture_handle);
		snd_pcm_hw_params_free(capture_params);
		return 1;
	}
	snd_pcm_hw_params(capture_handle, capture_params);
	snd_pcm_hw_params_free(capture_params);

	// Prepare the PCM playback stream
	err = snd_pcm_prepare(playback_handle);
	if (err < 0) {
		fprintf(stderr, "Error preparing playback device %s: %s\n", playback_device, snd_strerror(err));
		snd_pcm_close(playback_handle);
		return 1;
	}

	// Prepare the PCM capture stream
	err = snd_pcm_prepare(capture_handle);
	if (err < 0) {
		fprintf(stderr, "Error preparing playback device %s: %s\n", playback_device, snd_strerror(err));
		snd_pcm_close(playback_handle);
		return 1;
	}

	printf("Playback and capture devices configured successfully.\n");

	// Create threads for playback and capture
	pthread_t playback_tid, capture_tid;
	pthread_create(&playback_tid, NULL, playback_thread, NULL);
	pthread_create(&capture_tid, NULL, capture_thread, NULL);

	// Perform pause/resume in the main loop
	for (i = 0; i < pause_count; i++) {
		snd_pcm_state_t state = snd_pcm_state(playback_handle);

		while (state != SND_PCM_STATE_RUNNING) {
			usleep(10000); // Wait until playback is running
			state = snd_pcm_state(playback_handle);
		}
		// Pause playback device
		err = snd_pcm_pause(playback_handle, 1);
		if (err < 0) {
			fprintf(stderr, "Error pausing playback device %s at iteration %d: %s\n", playback_device, i, snd_strerror(err));
			break;
		}
		("Playback device %s paused at iteration %d.\n", playback_device, i);

		// Pause capture device
		err = snd_pcm_pause(capture_handle, 1);
		if (err < 0) {
			fprintf(stderr, "Error pausing capture device %s at iteration %d: %s\n", capture_device, i, snd_strerror(err));
			break;
		}
		printf("Capture device %s paused at iteration %d.\n", capture_device, i);

		usleep(10000); // Simulate a short pause

		// Resume playback device
		err = snd_pcm_pause(playback_handle, 0);
		if (err < 0) {
			fprintf(stderr, "Error resuming playback device %s at iteration %d: %s\n", playback_device, i, snd_strerror(err));
			break;
		}
		printf("Playback device %s resumed at iteration %d.\n", playback_device, i);

		// Resume capture device
		err = snd_pcm_pause(capture_handle, 0);
		if (err < 0) {
			fprintf(stderr, "Error resuming capture device %s at iteration %d: %s\n", capture_device, i, snd_strerror(err));
			break;
		}
		printf("Capture device %s resumed at iteration %d.\n", capture_device, i);
	}

	// Signal playback and capture threads to stop
	stop_threads = true;

	// Wait for playback and capture threads to finish
	pthread_join(playback_tid, NULL);
	pthread_join(capture_tid, NULL);

	// Close PCM devices
	cleanup_pcm_handles();

	printf("PCM devices closed.\n");
	if (i < pause_count - 1)
		return 1; // Return error if any pause/resume failed
	return 0; // Return success if all operations were successful
	
}

int main(int argc, char *argv[]) {
	// Initialize ALSA
	snd_lib_error_set_handler(NULL);

	// Check for user input for pause_count
	if (argc > 1) {
		pause_count = atoi(argv[1]); // Convert command-line argument to integer
		if (pause_count <= 0) {
			fprintf(stderr, "Invalid pause_count value. It must be a positive integer.\n");
			return 1;
		}
	}

	// check for user input for playback and capture devices and run pause/resume only for the specified combination
	if (argc > 3) {
		int playback_device_id = atoi(argv[2]); // Convert playback device id
		int capture_device_id = atoi(argv[3]);  // Convert capture device id
		char capture_device[MAX_DEVICE_NAME_LENGTH];
		char playback_device[MAX_DEVICE_NAME_LENGTH];
	
		snprintf(playback_device, MAX_DEVICE_NAME_LENGTH, "hw:0,%d", playback_device_id);
		snprintf(capture_device, MAX_DEVICE_NAME_LENGTH, "hw:0,%d", capture_device_id);
		// run pause/resume test
		if (run_pause_resume_test(playback_device, capture_device) != 0) {
			fprintf(stderr, "Pause/Resume test failed for playback device: %s and capture device: %s\n",
				playback_device, capture_device);
			return 1;
		}
		printf("Pause/Resume test completed successfully for playback device: %s and capture device: %s\n",
			playback_device, capture_device);

		return 0;
	}

	// List available PCM devices
	list_pcm_devices();

	// run pause/resume test with 1 playback and 1 capture device
	if (num_playback_devices == 0 || num_capture_devices == 0) {
		fprintf(stderr, "No playback or capture devices found.\n");
		return 1;
	}
	
	// loop through all capture devices for each playback device
	for (int i = 0; i < num_playback_devices; i++) {
		for (int j = 0; j < num_capture_devices; j++) {
			printf("Running pause/resume test for playback device: %s and capture device: %s\n",
				playback_devices[i], capture_devices[j]);

			// reset stop_threads flag
			stop_threads = false;

			// run pause/resume test
			if (run_pause_resume_test(playback_devices[i], capture_devices[j]) != 0) {
				fprintf(stderr, "Pause/Resume test failed for playback device: %s and capture device: %s\n",
					playback_devices[i], capture_devices[j]);
				return 1;
			}
			// Wait before next test
			printf("Pause/Resume test completed for playback device: %s and capture device: %s\n",
				playback_devices[i], capture_devices[j]);
			printf("Waiting before next test...\n");
			// Sleep for 3 seconds before next test
			usleep(3000000);

		}
	}

	printf("Pause/Resume test completed successfully.\n");
	return 0;
}