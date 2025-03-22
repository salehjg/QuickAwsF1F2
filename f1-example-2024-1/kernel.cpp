#define N 128
#define DATA_SIZE 1 << 10

// Tripcount identifiers
const int c_len = DATA_SIZE;
const int c_n = N;

// This kernel is optimized to access only one global variable in a pipelined
// loop. This will improve the II and increase throughput of the kernel.

extern "C" {
    void vadd_pipelined(int *c, const int *a, const int *b, const int len) {
#pragma HLS INTERFACE m_axi port = c offset = slave bundle = gmem
#pragma HLS INTERFACE m_axi port = a offset = slave bundle = gmem
#pragma HLS INTERFACE m_axi port = b offset = slave bundle = gmem
#pragma HLS INTERFACE s_axilite port = c bundle = control
#pragma HLS INTERFACE s_axilite port = a bundle = control
#pragma HLS INTERFACE s_axilite port = b bundle = control
#pragma HLS INTERFACE s_axilite port = len bundle = control
#pragma HLS INTERFACE s_axilite port = return bundle = control

        int result[N];
        int iterations = len / N;

        // Default behavior of V++ will pipeline the outer loop. Since we have
        // multiple inner loops, the pipelining will fail. We can instead pipeline
        // the inner loops using the HLS PIPELINE pragma to guide the compiler.
        vadd_pipeline:
            for (int i = 0; i < iterations; i++) {
#pragma HLS LOOP_TRIPCOUNT min=c_len/c_n max=c_len/c_n

                // Pipelining loops that access only one variable is the ideal way to
                // increase the global memory bandwidth.
                read_a:
                    for (int x = 0; x < N; ++x) {
#pragma HLS LOOP_TRIPCOUNT min=c_n max=c_n
#pragma HLS PIPELINE II=1
                        result[x] = a[i * N + x];
                    }

                read_b:
                    for (int x = 0; x < N; ++x) {
#pragma HLS LOOP_TRIPCOUNT min=c_n max=c_n
#pragma HLS PIPELINE II=1
                        result[x] += b[i * N + x];
                    }

                write_c:
                    for (int x = 0; x < N; ++x) {
#pragma HLS LOOP_TRIPCOUNT min=c_n max=c_n
#pragma HLS PIPELINE II=1
                        c[i * N + x] = result[x];
                    }
            }
    }
}