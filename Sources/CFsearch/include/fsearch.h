#ifndef FSEARCH_BRIDGE_H
#define FSEARCH_BRIDGE_H

// All strings are UTF-8 and NUL terminated. Inputs are borrowed for the call.
// On failure, open sets an owned error string. Release it with string_free.
void *fsearch_sample_open(const char *directory, char **error);
// The returned JSON string is owned by the caller; release with string_free.
char *fsearch_sample_search(void *handle, const char *request_json);
// Debug builds only: explicit fault injection; normal queries never trigger it.
char *fsearch_sample_test_panic(void *handle, const char *request_json);
// No concurrent calls or close while a call is in progress on this handle.
void fsearch_sample_close(void *handle);
void fsearch_string_free(char *value);

// Opt-in, process-confined validation Engine. One per process. All strings are
// UTF-8 and NUL terminated; inputs are borrowed for the call. On failure, open
// sets an owned error string. Release it and returned JSON strings with
// string_free. No concurrent calls or close while a call is in progress.
// Closing releases the caller's reference; upstream workers stop at process exit.
void *fsearch_engine_open(const char *directory, const char *index, char **error);
char *fsearch_engine_search(void *handle, const char *request_json);
// Debug builds only: explicit Engine fault injection.
char *fsearch_engine_test_panic(void *handle, const char *request_json);
char *fsearch_engine_status(void *handle);
char *fsearch_engine_changes(void *handle);
void fsearch_engine_save(void *handle);
void fsearch_engine_close(void *handle);

#endif
