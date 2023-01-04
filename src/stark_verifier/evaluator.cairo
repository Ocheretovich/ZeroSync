from starkware.cairo.common.alloc import alloc
from starkware.cairo.common.pow import pow
from stark_verifier.air.air_instance import AirInstance, ConstraintCompositionCoefficients
from stark_verifier.air.pub_inputs import PublicInputs, MemEntry

from stark_verifier.air.transitions.frame import (
    EvaluationFrame,
    evaluate_transition,
    evaluate_aux_transition,
)

// Main segment column indices with boundary constraints
const MEM_A_TRACE_OFFSET = 19;
const MEM_P_TRACE_OFFSET = 17;

// Aux segment column indices with boundary constraints
const P_M_OFFSET = 8;
const P_M_WIDTH = 4;
const A_RC_PRIME_OFFSET = 12;
const P_M_LAST = P_M_OFFSET + P_M_WIDTH - 1;
const A_RC_PRIME_FIRST = A_RC_PRIME_OFFSET;
const A_RC_PRIME_LAST = A_RC_PRIME_OFFSET + 2;

// TODO: Functions to evaluate transitions and combine evaluation should be autogenerated
// from a constraint description language instead of hand-coded.
func evaluate_constraints{
    range_check_ptr
}(
    air: AirInstance,
    coeffs: ConstraintCompositionCoefficients,
    ood_main_trace_frame: EvaluationFrame,
    ood_aux_trace_frame: EvaluationFrame,
    aux_trace_rand_elements: felt**,
    z: felt,
) -> felt {
    alloc_locals;

    // 1 ----- evaluate transition constraints ----------------------------------------------------

    // Evaluate main trace
    let (t_evaluations1: felt*) = alloc();
    evaluate_transition(
        ood_main_trace_frame, 
        t_evaluations1,
    );

    // Evaluate auxiliary trace
    let (t_evaluations2: felt*) = alloc();
    evaluate_aux_transition(
        ood_main_trace_frame,
        ood_aux_trace_frame, 
        aux_trace_rand_elements,
        t_evaluations2,
    );

    // Combine evaluations
    let result = combine_evaluations(
        t_evaluations1,
        t_evaluations2,
        z,
        air,
        coeffs,
    );

    // 2 ----- evaluate boundary constraints ------------------------------------------------

    let (b_evaluations1: felt*) = alloc();
    assert b_evaluations1[0] = ood_main_trace_frame.current[MEM_A_TRACE_OFFSET] - air.pub_inputs.init._pc;
    assert b_evaluations1[1] = ood_main_trace_frame.current[MEM_A_TRACE_OFFSET] - air.pub_inputs.fin._pc;
    assert b_evaluations1[2] = ood_main_trace_frame.current[MEM_P_TRACE_OFFSET] - air.pub_inputs.init._ap;
    assert b_evaluations1[3] = ood_main_trace_frame.current[MEM_P_TRACE_OFFSET] - air.pub_inputs.fin._ap;

    let (b_evaluations2: felt*) = alloc();
    let r = reduce_pub_mem(air.pub_inputs, aux_trace_rand_elements);
    assert b_evaluations2[0] = ood_aux_trace_frame.current[P_M_LAST] - r;
    assert b_evaluations2[1] = ood_aux_trace_frame.current[A_RC_PRIME_FIRST] - air.pub_inputs.rc_min;
    assert b_evaluations2[2] = ood_aux_trace_frame.current[A_RC_PRIME_LAST] - air.pub_inputs.rc_max;

    // All boundary (main and aux) constraints have the same degree, and one of two different 
    // divisors (constraining either the first or last step)
    let composition_degree = air.context.trace_length * air.ce_blowup_factor - 1;
    let trace_poly_degree = air.context.trace_length - 1;
    let divisor_degree = 1;
    let target_degree = composition_degree + divisor_degree;
    let degree_adjustment = target_degree - trace_poly_degree;
    let (xp) = pow(z, degree_adjustment);

    // Divisor evaluation for first step
    let z_1 = z - 1;

    // Divisor evaluation for last step
    let g = air.trace_domain_generator;
    let (g_n) = pow(g, air.context.trace_length - 1);
    let z_n = z - g_n;

    // Sum all constraint group evaluations
    let sum1 = 0;
    let sum2 = 0;

    // Main constraints
    let sum1 = sum1 + (coeffs.boundary_a[0] + coeffs.boundary_b[0] * xp) * b_evaluations1[0];
    let sum1 = sum1 + (coeffs.boundary_a[2] + coeffs.boundary_b[2] * xp) * b_evaluations1[2];
    let sum2 = sum2 + (coeffs.boundary_a[1] + coeffs.boundary_b[1] * xp) * b_evaluations1[1];
    let sum2 = sum2 + (coeffs.boundary_a[3] + coeffs.boundary_b[3] * xp) * b_evaluations1[3];

    // Aux constraints
    let sum1 = sum1 + (coeffs.boundary_a[5] + coeffs.boundary_b[5] * xp) * b_evaluations2[1];
    let sum2 = sum2 + (coeffs.boundary_a[4] + coeffs.boundary_b[4] * xp) * b_evaluations2[0];
    let sum2 = sum2 + (coeffs.boundary_a[6] + coeffs.boundary_b[6] * xp) * b_evaluations2[2];

    // Merge group sums
    let sum1 = sum1 / z_1;
    let sum2 = sum2 / z_n;
    let sum = sum1 + sum2;
    
    let result = result + sum; 
    return result;
}

func combine_evaluations{
        range_check_ptr
    }(
    t_evaluations1: felt*,
    t_evaluations2: felt*,
    x: felt,
    air: AirInstance,
    coeffs: ConstraintCompositionCoefficients,
) -> felt {
    alloc_locals;
    // Degrees needed to compute adjustments
    let composition_degree = air.context.trace_length * air.ce_blowup_factor - 1;
    let divisor_degree = air.context.trace_length - 1;
    let target_degree = composition_degree + divisor_degree;

    // Evaluate divisor
    let g = air.trace_domain_generator;
    let (numerator) = pow(x, air.context.trace_length);
    let numerator = numerator - 1;
    let (denominator) = pow(g, air.context.trace_length - 1);
    let denominator = x - denominator;
    let z = numerator / denominator;

    // Sum all constraint evaluations
    let sum = 0;


    // Merge evaluations for degree 1 constraints
    let evaluation_degree = (air.context.trace_length - 1);
    let degree_adjustment = target_degree - evaluation_degree;
    let (xp) = pow(x, degree_adjustment);
    let sum = sum + (coeffs.transition_a[15] + coeffs.transition_b[15] * xp) * t_evaluations1[15];
    
    // Merge evaluations for degree 2 constraints
    let evaluation_degree = 2 * (air.context.trace_length - 1);
    let degree_adjustment = target_degree - evaluation_degree;
    let (xp) = pow(x, degree_adjustment);
    let sum = sum + (coeffs.transition_a[0] + coeffs.transition_b[0] * xp) * t_evaluations1[0];
    let sum = sum + (coeffs.transition_a[1] + coeffs.transition_b[1] * xp) * t_evaluations1[1];
    let sum = sum + (coeffs.transition_a[2] + coeffs.transition_b[2] * xp) * t_evaluations1[2];
    let sum = sum + (coeffs.transition_a[3] + coeffs.transition_b[3] * xp) * t_evaluations1[3];
    let sum = sum + (coeffs.transition_a[4] + coeffs.transition_b[4] * xp) * t_evaluations1[4];
    let sum = sum + (coeffs.transition_a[5] + coeffs.transition_b[5] * xp) * t_evaluations1[5];
    let sum = sum + (coeffs.transition_a[6] + coeffs.transition_b[6] * xp) * t_evaluations1[6];
    let sum = sum + (coeffs.transition_a[7] + coeffs.transition_b[7] * xp) * t_evaluations1[7];
    let sum = sum + (coeffs.transition_a[8] + coeffs.transition_b[8] * xp) * t_evaluations1[8];
    let sum = sum + (coeffs.transition_a[9] + coeffs.transition_b[9] * xp) * t_evaluations1[9];
    let sum = sum + (coeffs.transition_a[10] + coeffs.transition_b[10] * xp) * t_evaluations1[10];
    let sum = sum + (coeffs.transition_a[11] + coeffs.transition_b[11] * xp) * t_evaluations1[11];
    let sum = sum + (coeffs.transition_a[12] + coeffs.transition_b[12] * xp) * t_evaluations1[12];
    let sum = sum + (coeffs.transition_a[13] + coeffs.transition_b[13] * xp) * t_evaluations1[13];
    let sum = sum + (coeffs.transition_a[14] + coeffs.transition_b[14] * xp) * t_evaluations1[14];

    // Merge evaluations for degree 4 constraints
    let evaluation_degree = 4 * (air.context.trace_length - 1);
    let degree_adjustment = target_degree - evaluation_degree;
    let (xp) = pow(x, degree_adjustment);
    let sum = sum + (coeffs.transition_a[16] + coeffs.transition_b[16] * xp) * t_evaluations1[16];
    let sum = sum + (coeffs.transition_a[17] + coeffs.transition_b[17] * xp) * t_evaluations1[17];
    let sum = sum + (coeffs.transition_a[18] + coeffs.transition_b[18] * xp) * t_evaluations1[18];
    let sum = sum + (coeffs.transition_a[19] + coeffs.transition_b[19] * xp) * t_evaluations1[19];
    let sum = sum + (coeffs.transition_a[20] + coeffs.transition_b[20] * xp) * t_evaluations1[20];
    let sum = sum + (coeffs.transition_a[21] + coeffs.transition_b[21] * xp) * t_evaluations1[21];
    let sum = sum + (coeffs.transition_a[22] + coeffs.transition_b[22] * xp) * t_evaluations1[22];
    let sum = sum + (coeffs.transition_a[23] + coeffs.transition_b[23] * xp) * t_evaluations1[23];
    let sum = sum + (coeffs.transition_a[24] + coeffs.transition_b[24] * xp) * t_evaluations1[24];
    let sum = sum + (coeffs.transition_a[25] + coeffs.transition_b[25] * xp) * t_evaluations1[25];
    let sum = sum + (coeffs.transition_a[26] + coeffs.transition_b[26] * xp) * t_evaluations1[26];
    let sum = sum + (coeffs.transition_a[27] + coeffs.transition_b[27] * xp) * t_evaluations1[27];
    let sum = sum + (coeffs.transition_a[28] + coeffs.transition_b[28] * xp) * t_evaluations1[28];
    let sum = sum + (coeffs.transition_a[29] + coeffs.transition_b[29] * xp) * t_evaluations1[29];
    let sum = sum + (coeffs.transition_a[30] + coeffs.transition_b[30] * xp) * t_evaluations1[30];

    // Merge evaluations for degree 2 auxiliary constraints
    let evaluation_degree = 2 * (air.context.trace_length-1);
    let degree_adjustment = target_degree - evaluation_degree;
    let (xp) = pow(x, degree_adjustment);
    let sum = sum + (coeffs.transition_a[31] + coeffs.transition_b[31] * xp) * t_evaluations2[0];
    let sum = sum + (coeffs.transition_a[32] + coeffs.transition_b[32] * xp) * t_evaluations2[1];
    let sum = sum + (coeffs.transition_a[33] + coeffs.transition_b[33] * xp) * t_evaluations2[2];
    let sum = sum + (coeffs.transition_a[34] + coeffs.transition_b[34] * xp) * t_evaluations2[3];
    let sum = sum + (coeffs.transition_a[35] + coeffs.transition_b[35] * xp) * t_evaluations2[4];
    let sum = sum + (coeffs.transition_a[36] + coeffs.transition_b[36] * xp) * t_evaluations2[5];
    let sum = sum + (coeffs.transition_a[37] + coeffs.transition_b[37] * xp) * t_evaluations2[6];
    let sum = sum + (coeffs.transition_a[38] + coeffs.transition_b[38] * xp) * t_evaluations2[7];
    let sum = sum + (coeffs.transition_a[39] + coeffs.transition_b[39] * xp) * t_evaluations2[8];
    let sum = sum + (coeffs.transition_a[40] + coeffs.transition_b[40] * xp) * t_evaluations2[9];
    let sum = sum + (coeffs.transition_a[41] + coeffs.transition_b[41] * xp) * t_evaluations2[10];
    let sum = sum + (coeffs.transition_a[42] + coeffs.transition_b[42] * xp) * t_evaluations2[11];
    let sum = sum + (coeffs.transition_a[43] + coeffs.transition_b[43] * xp) * t_evaluations2[12];
    let sum = sum + (coeffs.transition_a[44] + coeffs.transition_b[44] * xp) * t_evaluations2[13];
    let sum = sum + (coeffs.transition_a[45] + coeffs.transition_b[45] * xp) * t_evaluations2[14];
    let sum = sum + (coeffs.transition_a[46] + coeffs.transition_b[46] * xp) * t_evaluations2[15];
    let sum = sum + (coeffs.transition_a[47] + coeffs.transition_b[47] * xp) * t_evaluations2[16];
    let sum = sum + (coeffs.transition_a[48] + coeffs.transition_b[48] * xp) * t_evaluations2[17];

    // Divide by divisor evaluation. We can do this once at the end of merging because 
    // the divisor is identical for all constraints
    let sum = sum / z;

    return sum;
}

func reduce_pub_mem{
        range_check_ptr
    }(pub_inputs: PublicInputs*, aux_rand_elements: felt**) -> felt {
    alloc_locals;
    let rand_elements = aux_rand_elements[0];
    let mem = pub_inputs.mem;

    let z = rand_elements[0];
    let alpha = rand_elements[1];

    let (num) = pow(z, pub_inputs.mem_length);
    let den = _reduce_pub_mem(z, alpha, mem, pub_inputs.mem_length);
    return num / den;
}


func _reduce_pub_mem(
    z, alpha, mem: MemEntry*, mem_length
)-> felt {
    if (mem_length == 0){
        return 1;
    }
    let a = [mem].address;
    let v = [mem].value;
    let tmp1 = z - (a + alpha * v);
    let tmp2 = _reduce_pub_mem(z, alpha, mem + MemEntry.SIZE, mem_length - 1);
    return tmp1 * tmp2;
}