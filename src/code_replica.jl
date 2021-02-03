"""
$(SIGNATURES)

Generate a code replica for a signal from satellite system `S`. The 
replica contains `num_samples` prompt samples as well as an additional
number of early and late samples specified by `correlator_sample_shifts`.
The codefrequency is specified by `code_frequency`, while the sampling
rate is given by `sampling_frequency`. The phase of the first prompt 
sample is given by `start_code_phase`. The generated signal is returned
in the array `code_replica` with the first generated sample written to 
index start_sample.
"""
function gen_code_replica!(
    code_replica,
    system::AbstractGNSS,
    code_frequency,
    sampling_frequency,
    start_code_phase::AbstractFloat,
    start_sample::Integer,
    num_samples::Integer,
    correlator_sample_shifts::SVector,
    prn::Integer
)
    most_early_sample_shift = correlator_sample_shifts[end]
    most_late_sample_shift  = correlator_sample_shifts[1]
    early_late_samples = most_early_sample_shift - most_late_sample_shift
    code_length = get_code_length(system)
    fixed_point = sizeof(Int) * 8 - 1 - min_bits_for_code_length(system)
    delta = floor(Int, code_frequency * 1 << fixed_point / sampling_frequency)
    modded_start_code_phase = mod(
        start_code_phase + (most_late_sample_shift - start_sample) * code_frequency/sampling_frequency,
        code_length * get_secondary_code_length(system)
        )
    fixed_point_start_code_phase = floor(Int, modded_start_code_phase * 1 << fixed_point)
    code_length_fixed_point = code_length << fixed_point

    end_code_phase = modded_start_code_phase + (start_sample + num_samples + early_late_samples) * code_frequency / sampling_frequency
    number_of_iterations = floor(Int, end_code_phase / code_length)
    first_iteration = floor(Int, (modded_start_code_phase + start_sample * code_frequency / sampling_frequency) / code_length)
    fixed_point_code_phase = (start_sample - 1) * delta + fixed_point_start_code_phase - (first_iteration - 1) * code_length_fixed_point

    samples_left = num_samples + early_late_samples
    for m = first_iteration:number_of_iterations
        phase_correction = m * code_length_fixed_point
        number_of_samples = min(samples_left,
            floor(Int, (2 * code_length_fixed_point - fixed_point_code_phase - delta) / delta)
        )
        samples_left -= number_of_samples
        @inbounds for i = start_sample:start_sample+number_of_samples-1
            fixed_point_code_phase = i * delta + fixed_point_start_code_phase - phase_correction
            code_index = fixed_point_code_phase >> fixed_point
            code_replica[i] = get_code_unsafe(system, code_index, prn)
        end
        start_sample += number_of_samples
    end
    code_replica
end

"""
$(SIGNATURES)

Updates the code phase.
"""
function update_code_phase(
    system::AbstractGNSS,
    num_samples,
    code_frequency,
    sampling_frequency,
    start_code_phase,
    secondary_code_or_bit_found
)
    if get_data_frequency(system) == 0Hz
        secondary_code_or_bit_length = get_secondary_code_length(system)
    else
        secondary_code_or_bit_length =
            Int(get_code_frequency(system) / (get_data_frequency(system) * get_code_length(system)))
    end
    code_length = get_code_length(system) *
        (secondary_code_or_bit_found ? secondary_code_or_bit_length : 1)
    mod(code_frequency * num_samples / sampling_frequency + start_code_phase, code_length)
#    fixed_point = sizeof(Int) * 8 - 1 - min_bits_for_code_length(S)
#    delta = floor(Int, code_frequency * 1 << fixed_point / sampling_frequency)
#    fixed_point_start_phase = floor(Int, start_code_phase * 1 << fixed_point)
#    phase_fixed_point = delta * num_samples + fixed_point_start_phase
#    mod(phase_fixed_point / 1 << fixed_point, code_length)
end

"""
$(SIGNATURES)

Calculates the current code frequency.
"""
function get_current_code_frequency(system::AbstractGNSS, code_doppler)
    code_doppler + get_code_frequency(system)
end
