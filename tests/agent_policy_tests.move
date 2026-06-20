#[test_only]
module sentinel::agent_policy_tests;

// Run with `sui move test` from the contracts directory.

use sentinel::budget;
use sentinel::agent_policy;
use sui::{clock, object, tx_context};

const AGENT: address = @0xA11CE;
const OWNER: address = @0xB0B;
const POOL: address = @0xD00D;
const BM: address = @0xBABA;

fun fresh_policy(ctx: &mut TxContext): agent_policy::AgentPolicy {
    agent_policy::new_for_testing(
        OWNER,
        AGENT,
        0, // active
        10_000, // expires_at_ms
        100, // global_budget
        0, // spent_budget
        25, // max_per_order
        50, // max_slippage_bps
        POOL,
        100, // pool_budget
        0, // pool_spent
        25, // pool_max_order_size
        50, // pool_max_slippage_bps
        BM,
        ctx,
    )
}

#[test]
fun budget_allows_available_spend() {
    budget::assert_budget_available(20, 100, 25, 999);
}

#[test, expected_failure(abort_code = 999)]
fun budget_rejects_overspend() {
    budget::assert_budget_available(90, 100, 25, 999);
}

#[test]
fun valid_order_consumes_budget() {
    let mut ctx = tx_context::new_from_hint(AGENT, 1, 0, 0, 0);
    let clock = clock::create_for_testing(&mut ctx);
    let mut policy = fresh_policy(&mut ctx);

    agent_policy::validate_and_consume_for_testing(
        &mut policy,
        object::id_from_address(POOL),
        object::id_from_address(BM),
        1, // order_id
        25, // amount
        25, // max_slippage_bps
        &clock,
        &ctx,
    );

    assert!(agent_policy::spent_budget_for_testing(&policy) == 25, 1000);
    assert!(agent_policy::nonce_for_testing(&policy) == 1, 1001);

    agent_policy::destroy_for_testing(policy);
    clock.destroy_for_testing();
}

#[test]
fun cancel_releases_reservation() {
    let mut ctx = tx_context::new_from_hint(AGENT, 1, 0, 0, 0);
    let clock = clock::create_for_testing(&mut ctx);
    let mut policy = fresh_policy(&mut ctx);

    agent_policy::validate_and_consume_for_testing(
        &mut policy,
        object::id_from_address(POOL),
        object::id_from_address(BM),
        7,
        25,
        25,
        &clock,
        &ctx,
    );
    assert!(agent_policy::spent_budget_for_testing(&policy) == 25, 2000);

    agent_policy::release_reservation_for_testing(&mut policy, 7, &clock, &ctx);
    assert!(agent_policy::spent_budget_for_testing(&policy) == 0, 2001);

    agent_policy::destroy_for_testing(policy);
    clock.destroy_for_testing();
}

#[test, expected_failure(abort_code = 13)]
fun cancel_with_unknown_order_id_aborts() {
    let mut ctx = tx_context::new_from_hint(AGENT, 1, 0, 0, 0);
    let clock = clock::create_for_testing(&mut ctx);
    let mut policy = fresh_policy(&mut ctx);

    agent_policy::validate_and_consume_for_testing(
        &mut policy,
        object::id_from_address(POOL),
        object::id_from_address(BM),
        7,
        25,
        25,
        &clock,
        &ctx,
    );

    agent_policy::release_reservation_for_testing(&mut policy, 8, &clock, &ctx);

    agent_policy::destroy_for_testing(policy);
    clock.destroy_for_testing();
}

#[test, expected_failure(abort_code = 2)]
fun wrong_agent_cannot_consume_budget() {
    let mut ctx = tx_context::new_from_hint(@0xBAD, 2, 0, 0, 0);
    let clock = clock::create_for_testing(&mut ctx);
    let mut policy = fresh_policy(&mut ctx);

    agent_policy::validate_and_consume_for_testing(
        &mut policy,
        object::id_from_address(POOL),
        object::id_from_address(BM),
        1,
        1,
        1,
        &clock,
        &ctx,
    );

    agent_policy::destroy_for_testing(policy);
    clock.destroy_for_testing();
}

#[test, expected_failure(abort_code = 7)]
fun order_exceeding_budget_aborts() {
    let mut ctx = tx_context::new_from_hint(AGENT, 1, 0, 0, 0);
    let clock = clock::create_for_testing(&mut ctx);
    let mut policy = fresh_policy(&mut ctx);

    // max_per_order is 25, so 26 trips ORDER_TOO_LARGE (6) first; use a policy
    // whose per-order cap is high but budget is low by spending first.
    agent_policy::validate_and_consume_for_testing(
        &mut policy,
        object::id_from_address(POOL),
        object::id_from_address(BM),
        1,
        25,
        25,
        &clock,
        &ctx,
    );
    // global_budget 100, already spent 25; 4 * 25 = 100 -> the 5th 25 overspends.
    agent_policy::validate_and_consume_for_testing(&mut policy, object::id_from_address(POOL), object::id_from_address(BM), 2, 25, 25, &clock, &ctx);
    agent_policy::validate_and_consume_for_testing(&mut policy, object::id_from_address(POOL), object::id_from_address(BM), 3, 25, 25, &clock, &ctx);
    agent_policy::validate_and_consume_for_testing(&mut policy, object::id_from_address(POOL), object::id_from_address(BM), 4, 25, 25, &clock, &ctx);
    // spent now 100 == budget; next order overspends -> abort 7
    agent_policy::validate_and_consume_for_testing(&mut policy, object::id_from_address(POOL), object::id_from_address(BM), 5, 25, 25, &clock, &ctx);

    agent_policy::destroy_for_testing(policy);
    clock.destroy_for_testing();
}

#[test, expected_failure(abort_code = 5)]
fun unknown_pool_aborts() {
    let mut ctx = tx_context::new_from_hint(AGENT, 1, 0, 0, 0);
    let clock = clock::create_for_testing(&mut ctx);
    let mut policy = fresh_policy(&mut ctx);

    agent_policy::validate_and_consume_for_testing(
        &mut policy,
        object::id_from_address(@0xFEED), // not an allowed pool
        object::id_from_address(BM),
        1,
        10,
        10,
        &clock,
        &ctx,
    );

    agent_policy::destroy_for_testing(policy);
    clock.destroy_for_testing();
}
