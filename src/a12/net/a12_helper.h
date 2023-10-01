/*
 * Copyright: 2018-2020, Bjorn Stahl
 * License: 3-Clause BSD
 * Description: This is a set of helper functions to deal with the event loop
 * specifically for acting as a translation proxy between shmif- and a12. The
 * 'server' and 'client' naming is a misnomer as the 'server' act as a local
 * shmif server and remote a12 client, while the 'client' act as a local shmif
 * client and remote a12 server.
 */

#ifndef HAVE_A12_HELPER

enum a12helper_pollstate {
	A12HELPER_POLL_SHMIF = 1,
	A12HELPER_WRITE_OUT = 2,
	A12HELPER_DATA_IN = 4
};

struct a12helper_opts {
	struct a12_vframe_opts (*eval_vcodec)(
		struct a12_state* S, int segid, struct shmifsrv_vbuffer*, void* tag);
	void* tag;

/* Set to the maximum distance between acknowledged frame and pending outgoing
 * and halt releasing client vframe until that resets back to within tolerance.
 * This is a coarse congestion control mechanism, meant as a placeholder until
 * something more refined can be developed.
 *
 * At 'soft_block' only partial frame updates will be let through,
 * At 'block' all further updates will be deferred
 */
	size_t vframe_soft_block;
	size_t vframe_block;

/* a12cl_shmifsrv- specific: set to a valid local connection-point and incoming
 * EXIT_ events will be translated to DEVICE_NODE events, preventing the remote
 * side from closing the window */
 	const char* redirect_exit;

/* a12cl_shmifsrv- specific: set to a valid local connection-point and it will
 * be set as the DEVICE_NODE alternate for incoming connections */
	const char* devicehint_cp;

/* opendir to populate with b64[checksum] for fonts and other cacheables */
	int bcache_dir;
};

/*
 * Take a prenegotiated connection [S] and an accepted shmif client [C] and
 * use [fd_in, fd_out] (which can be set to the same and treated as a socket)
 * as the bitstream carrer.
 *
 * This will block until the connection is terminated.
 */
void a12helper_a12cl_shmifsrv(struct a12_state* S,
	struct shmifsrv_client* C, int fd_in, int fd_out, struct a12helper_opts);

/*
 * Take a prenegotiated connection [S] serialized over [fd_in/fd_out] and
 * map to connections accessible via the [cp] connection point.
 *
 * If a [prealloc] context is provided, it will be used instead of the [cp].
 * Note that it should come in a SEGID_UNKNOWN/SHMIF_NOACTIVATE state so
 * that the incoming events from the source will map correctly.
 *
 * Returns:
 * a12helper_pollstate bitmap
 *
 * Error codes:
 *  -EINVAL : invalid connection point
 *  -ENOENT : couldn't make shmif connection
 */
int a12helper_a12srv_shmifcl(
	struct arcan_shmif_cont* prealloc,
	struct a12_state* S, const char* cp, int fd_in, int fd_out);

uint8_t* a12helper_tob64(const uint8_t* data, size_t inl, size_t* outl);
bool a12helper_fromb64(const uint8_t* instr, size_t lim, uint8_t outb[static 32]);

#endif
