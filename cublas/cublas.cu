#include <stdio.h>
#include <cublas_v2.h>

void matrixMulCPU(float *C, const float *A, const float *B, unsigned int hA, unsigned int wA, unsigned int wB)
{
	for (int i = 0; i < hA; ++i)
	{
		for (int j = 0; j < wB; ++j)
		{
			float sum = 0;
			for (int k = 0; k < wA; ++k)
			{
				sum += A[i * wA + k] * B[k * wB + j];
			}
			C[i * wB + j] = sum;
		}
	}
}

int main(int argc, char *argv[])
{
	// Initialize constants.
	int block_size = 32;
	int uiWA = 2 * block_size * 5;
	int uiHA = 4 * block_size * 5;
	int uiWB = 2 * block_size * 5;
	int uiHB = 4 * block_size * 5;
	int uiWC = 2 * block_size * 5;
	int uiHC = 4 * block_size * 5;
	unsigned int size_A = uiWA * uiHA;
	unsigned int size_B = uiWB * uiHB;
	unsigned int size_C = uiWC * uiHC;
	unsigned int mem_size_A = sizeof(float) * size_A;
	unsigned int mem_size_B = sizeof(float) * size_B;
	unsigned int mem_size_C = sizeof(float) * size_C;

	// Allocates matrices a, b and c in host memory.
	float *h_A = (float *)malloc(mem_size_A);
	float *h_B = (float *)malloc(mem_size_B);
	float *h_C = (float *)malloc(mem_size_C);

	// Initialize matrices a and b.
	srand(2006);
	for (int i = 0; i < size_A; ++i)
	{
		h_A[i] = rand() / (float)RAND_MAX;
	}
	for (int i = 0; i < size_B; ++i)
	{
		h_B[i] = rand() / (float)RAND_MAX;
	}

	// Allocate matrices a, b and c in device memory.
	float *d_A, *d_B, *d_C;
	cudaMalloc((void **)&d_A, mem_size_A);
	cudaMalloc((void **)&d_B, mem_size_B);
	cudaMalloc((void **)&d_C, mem_size_C);

	// Copy matrices a and b from host memory to device memory.
	cudaMemcpy(d_A, h_A, mem_size_A, cudaMemcpyHostToDevice);
	cudaMemcpy(d_B, h_B, mem_size_B, cudaMemcpyHostToDevice);

	// Determine the number of threads per block and the number of blocks per grid.
	dim3 numThreadsPerBlock(block_size, block_size);
	dim3 numBlocksPerGrid(uiWC / numThreadsPerBlock.x, uiHC / numThreadsPerBlock.y);

	// Initialize a cublas handle.
	cublasHandle_t handle;
	cublasCreate(&handle);

	// CUBLAS is column primary.
	const float alpha = 1.0f;
	const float beta  = 0.0f;
	cublasSgemm(handle, CUBLAS_OP_N, CUBLAS_OP_N, uiWB, uiHA, uiWA, &alpha, d_B, uiWB, d_A, uiWA, &beta, d_C, uiWA);

	// Measure the performance of cublasSgemm over a number of iterations.
	cudaEvent_t start, stop;
	cudaEventCreate(&start);
	cudaEventCreate(&stop);
	cudaEventRecord(start, 0);
	int numIterations = 30;
	for (int i = 0; i < numIterations; ++i)
	{
		cublasSgemm(handle, CUBLAS_OP_N, CUBLAS_OP_N, uiWB, uiHA, uiWA, &alpha, d_B, uiWB, d_A, uiWA, &beta, d_C, uiWA);
	}
	cudaEventRecord(stop, 0);
	cudaEventSynchronize(stop);
	float elapsed;
	cudaEventElapsedTime(&elapsed, start, stop);

	// Compute and print the GLOPS/s performance metric.
	printf("%.2f GFLOP/s\n", (2.0f * uiWA * uiHA * uiWB * numIterations * 1e-9f) / (elapsed / 1000.0f));

	// Copy matrix c from device memory to host memory.
	cudaMemcpy(h_C, d_C, mem_size_C, cudaMemcpyDeviceToHost);

	// Compute reference solution.
	float *ref = (float *)malloc(mem_size_C);
	matrixMulCPU(ref, h_A, h_B, uiHA, uiWA, uiWB);

	// Validate the result.
	for (int i = 0; i < size_C; ++i)
	{
		float actual = h_C[i];
		float expected = ref[i];
		if (fabs(actual - expected) / fabs(actual) / uiWA > 1e-7)
		{
			printf("h_C[%d] = %f, expected = %f\n", i, actual, expected);
			break;
		}
	}

	// Cleanup.
	free(ref);
	cublasDestroy(handle);
	cudaFree(d_C);
	cudaFree(d_B);
	cudaFree(d_A);
	cudaDeviceReset();
	free(h_C);
	free(h_B);
	free(h_A);
}
