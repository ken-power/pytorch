#include <ATen/ATen.h>
#include <ATen/native/cuda/SortingCommon.cuh>

#include <THC/THCThrustAllocator.cuh>
#include <thrust/device_ptr.h>
#include <thrust/execution_policy.h>
#include <thrust/sort.h>
#include <thrust/unique.h>
#include <thrust/device_ptr.h>

namespace at { namespace native {

void index_put_with_sort_kernel_thrust_helper(Tensor &linearIndex, Tensor &orig_indices, Tensor &sorted_indices, int64_t num_indices) {
  sorted_indices.copy_(linearIndex);
  const cudaStream_t stream = at::cuda::getCurrentCUDAStream();
  auto allocator = THCThrustAllocator(globalContext().lazyInitCUDA());
  auto policy = thrust::cuda::par(allocator).on(stream);

  using device_ptr = thrust::device_ptr<int64_t>;

  // Fill sortedOrigIndices with sequential indices
  const auto count_iter = thrust::counting_iterator<int64_t>(0);
  auto orig_data = device_ptr(orig_indices.data_ptr<int64_t>());
  thrust::copy(policy, count_iter, count_iter + num_indices, orig_data);

  // Sort the inputs into sorted with the corresponding indices; we
  // don't need a stable or multidimensional sort, so just use Thrust
  // directly
  // Sort; a stable sort is not required
  // NB - not passing comparator causes thrust to use radix sort, and it hurts perf A LOT, at least for medium (few K) sized indices
  auto sorted_data = device_ptr(sorted_indices.data_ptr<int64_t>());
  thrust::sort_by_key(policy, sorted_data, sorted_data + num_indices, orig_data, LTOp<int64_t>());
}

template<typename index_t>
int embedding_renorm_cuda_unique_copy(Tensor &indices_contig, Tensor &unique_indices) {
  cudaStream_t stream = at::cuda::getCurrentCUDAStream();
  auto allocator = THCThrustAllocator(globalContext().lazyInitCUDA());
  auto policy = thrust::cuda::par(allocator).on(stream);

  using device_ptr = thrust::device_ptr<index_t>;

  auto num_indices = indices_contig.numel();
  auto indices_data = device_ptr(indices_contig.data_ptr<index_t>());
  auto unique_data = device_ptr(unique_indices.data_ptr<index_t>());
  auto end = thrust::unique_copy(policy, indices_data, indices_data + num_indices, unique_data);
  auto num_unique_indices = static_cast<int>(end - unique_data);
  return num_unique_indices;
}

template
int embedding_renorm_cuda_unique_copy<int>(Tensor &indices_contig, Tensor &unique_indices);
template
int embedding_renorm_cuda_unique_copy<int64_t>(Tensor &indices_contig, Tensor &unique_indices);

}}
