#include <nvbench_helper.cuh>
#include <cub/device/device_partition.cuh>

// %RANGE% TUNE_TRANSPOSE trp 0:1:1
// %RANGE% TUNE_LOAD ld 0:1:1
// %RANGE% TUNE_ITEMS_PER_THREAD ipt 7:24:1
// %RANGE% TUNE_THREADS_PER_BLOCK tpb 128:1024:32
// %RANGE% CUB_DETAIL_L2_BACKOFF_NS l2b 0:1200:5
// %RANGE% CUB_DETAIL_L2_WRITE_LATENCY_NS l2w 0:1200:5

constexpr bool keep_rejects = true;
constexpr bool may_alias = false;

#if !TUNE_BASE
#if TUNE_TRANSPOSE == 0
#define TUNE_LOAD_ALGORITHM cub::BLOCK_LOAD_DIRECT
#else // TUNE_TRANSPOSE == 1
#define TUNE_LOAD_ALGORITHM cub::BLOCK_LOAD_WARP_TRANSPOSE
#endif // TUNE_TRANSPOSE

#if TUNE_LOAD == 0
#define TUNE_LOAD_MODIFIER cub::LOAD_DEFAULT
#else // TUNE_LOAD == 1
#define TUNE_LOAD_MODIFIER cub::LOAD_CA
#endif // TUNE_LOAD

template <typename InputT>
struct policy_hub_t
{
  struct policy_t : cub::ChainedPolicy<300, policy_t, policy_t>
  {
    static constexpr int NOMINAL_4B_ITEMS_PER_THREAD = TUNE_ITEMS_PER_THREAD;

    static constexpr int ITEMS_PER_THREAD =
      CUB_MIN(NOMINAL_4B_ITEMS_PER_THREAD,
              CUB_MAX(1, (NOMINAL_4B_ITEMS_PER_THREAD * 4 / sizeof(InputT))));

    using SelectIfPolicyT = cub::AgentSelectIfPolicy<TUNE_THREADS_PER_BLOCK,
                                                     ITEMS_PER_THREAD,
                                                     TUNE_LOAD_ALGORITHM,
                                                     TUNE_LOAD_MODIFIER,
                                                     cub::BLOCK_SCAN_WARP_SCANS>;
  };

  using MaxPolicy = policy_t;
};
#endif // !TUNE_BASE

template <class T>
struct less_then_t 
{
  T m_val;

  __device__ bool operator()(const T &val) const { return val < m_val; }
};

template <typename T>
T value_from_entropy(double percentage) 
{
  if (percentage == 1) 
  {
    return std::numeric_limits<T>::max();
  }
  
  const auto max_val = static_cast<double>(std::numeric_limits<T>::max());
  const auto min_val = static_cast<double>(std::numeric_limits<T>::lowest());
  const auto result = min_val + percentage * max_val - percentage * min_val;
  return static_cast<T>(result);
}

template <typename T, typename OffsetT>
void partition(nvbench::state &state, nvbench::type_list<T, OffsetT>)
{
  using input_it_t = const T*;
  using flag_it_t = cub::NullType*;
  using output_it_t = T*;
  using num_selected_it_t = OffsetT*;
  using select_op_t = less_then_t<T>;
  using equality_op_t = cub::NullType;
  using offset_t = OffsetT;

  #if !TUNE_BASE
  using policy_t = policy_hub_t<T>;
  using dispatch_t = cub::DispatchSelectIf<input_it_t,
                                           flag_it_t,
                                           output_it_t,
                                           num_selected_it_t,
                                           select_op_t,
                                           equality_op_t,
                                           offset_t,
                                           keep_rejects,
                                           may_alias,
                                           policy_t>;
  #else // TUNE_BASE
  using dispatch_t = cub::DispatchSelectIf<input_it_t,
                                           flag_it_t,
                                           output_it_t,
                                           num_selected_it_t,
                                           select_op_t,
                                           equality_op_t,
                                           offset_t,
                                           keep_rejects,
                                           may_alias>;
  #endif // !TUNE_BASE

  // Retrieve axis parameters
  const auto elements = static_cast<std::size_t>(state.get_int64("Elements{io}"));
  const bit_entropy entropy = str_to_entropy(state.get_string("Entropy"));

  T min_val = std::numeric_limits<T>::lowest();
  T max_val = std::numeric_limits<T>::max();
  T val = value_from_entropy<T>(entropy_to_probability(entropy));
  select_op_t select_op{val};

  thrust::device_vector<T> in(elements);
  thrust::device_vector<offset_t> num_selected(1);

  gen(seed_t{}, in);

  thrust::device_vector<T> out(elements);

  input_it_t d_in = thrust::raw_pointer_cast(in.data());
  flag_it_t d_flags = nullptr;
  output_it_t d_out = thrust::raw_pointer_cast(out.data());
  num_selected_it_t d_num_selected = thrust::raw_pointer_cast(num_selected.data());

  state.add_element_count(elements);
  state.add_global_memory_reads<T>(elements);
  state.add_global_memory_writes<T>(elements);
  state.add_global_memory_writes<offset_t>(1);

  std::size_t temp_size{};
  dispatch_t::Dispatch(nullptr,
                       temp_size,
                       d_in,
                       d_flags,
                       d_out,
                       d_num_selected,
                       select_op,
                       equality_op_t{},
                       elements,
                       0);

  thrust::device_vector<nvbench::uint8_t> temp(temp_size);
  auto *temp_storage = thrust::raw_pointer_cast(temp.data());

  state.exec([&](nvbench::launch &launch) {
    dispatch_t::Dispatch(temp_storage,
                         temp_size,
                         d_in,
                         d_flags,
                         d_out,
                         d_num_selected,
                         select_op,
                         equality_op_t{},
                         elements,
                         launch.get_stream());
  });
}

NVBENCH_BENCH_TYPES(partition, NVBENCH_TYPE_AXES(fundamental_types, offset_types))
  .set_name("cub::DevicePartition::If")
  .set_type_axes_names({"T{ct}", "OffsetT{ct}"})
  .add_int64_power_of_two_axis("Elements{io}", nvbench::range(16, 28, 4))
  .add_string_axis("Entropy", {"1.000", "0.811", "0.544", "0.337", "0.201", "0.000"});
