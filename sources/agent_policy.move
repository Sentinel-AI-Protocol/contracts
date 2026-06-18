module sentinel::agent_policy;

use sentinel::{activity_log, budget};
use sui::{
    clock::{Self, Clock},
    vec_map::{Self, VecMap},
};

const STATUS_ACTIVE: u8 = 0;
const STATUS_PAUSED: u8 = 1;
const STATUS_REVOKED: u8 = 2;

const E_NOT_OWNER: u64 = 1;
const E_NOT_AGENT: u64 = 2;
const E_POLICY_NOT_ACTIVE: u64 = 3;
const E_POLICY_EXPIRED: u64 = 4;
const E_POOL_NOT_ALLOWED: u64 = 5;
const E_ORDER_TOO_LARGE: u64 = 6;
const E_BUDGET_EXCEEDED: u64 = 7;
const E_SLIPPAGE_EXCEEDED: u64 = 8;
const E_BALANCE_MANAGER_MISMATCH: u64 = 9;
const E_REVOKED: u64 = 10;
const E_POOL_CONFIG_LENGTH_MISMATCH: u64 = 11;
const E_BALANCE_MANAGER_ALREADY_SET: u64 = 12;
const E_UNKNOWN_RESERVATION: u64 = 13;

/// Sentinel-controlled zero address used as the "unset" sentinel for the
/// balance manager binding. A policy may be created before its DeepBook
/// BalanceManager exists; `set_balance_manager` binds it exactly once.
const UNSET_ADDRESS: address = @0x0;

public struct AgentPolicy has key {
    id: UID,
    owner: address,
    agent: address,
    status: u8,
    created_at_ms: u64,
    expires_at_ms: u64,
    global_budget: u64,
    spent_budget: u64,
    max_per_order: u64,
    max_slippage_bps: u64,
    balance_manager_id: ID,
    balance_manager_bound: bool,
    pools: vector<PoolRule>,
    /// order_id -> reserved quote units, so a cancel can release exactly what
    /// a place reserved. Bounded by the agent's open-order count.
    reservations: VecMap<u128, Reservation>,
    nonce: u64,
}

public struct PoolRule has copy, drop, store {
    pool_id: ID,
    max_quote_budget: u64,
    spent_quote: u64,
    max_order_size: u64,
    max_slippage_bps: u64,
    enabled: bool,
}

public struct Reservation has copy, drop, store {
    pool_id: ID,
    amount: u64,
}

/// Create a policy with independent per-pool budgets. `pool_addresses` and the
/// per-pool config vectors must all share the same length. Pass an empty /
/// `0x0` balance manager to bind it later via `set_balance_manager`.
public fun create_policy(
    agent: address,
    _name: vector<u8>,
    global_budget: u64,
    max_per_order: u64,
    max_slippage_bps: u64,
    expires_at_ms: u64,
    pool_addresses: vector<address>,
    pool_max_quote_budgets: vector<u64>,
    pool_max_order_sizes: vector<u64>,
    pool_max_slippage_bps: vector<u64>,
    balance_manager_address: address,
    clock: &Clock,
    ctx: &mut TxContext,
) {
    let len = pool_addresses.length();
    assert!(
        pool_max_quote_budgets.length() == len
            && pool_max_order_sizes.length() == len
            && pool_max_slippage_bps.length() == len,
        E_POOL_CONFIG_LENGTH_MISMATCH,
    );

    let mut pools = vector[];
    let mut i = 0;
    while (i < len) {
        pools.push_back(PoolRule {
            pool_id: object::id_from_address(pool_addresses[i]),
            max_quote_budget: pool_max_quote_budgets[i],
            spent_quote: 0,
            max_order_size: pool_max_order_sizes[i],
            max_slippage_bps: pool_max_slippage_bps[i],
            enabled: true,
        });
        i = i + 1;
    };

    let id = object::new(ctx);
    let policy_id = id.to_inner();
    let owner = ctx.sender();
    let now_ms = clock.timestamp_ms();
    let balance_manager_bound = balance_manager_address != UNSET_ADDRESS;
    let policy = AgentPolicy {
        id,
        owner,
        agent,
        status: STATUS_ACTIVE,
        created_at_ms: now_ms,
        expires_at_ms,
        global_budget,
        spent_budget: 0,
        max_per_order,
        max_slippage_bps,
        balance_manager_id: object::id_from_address(balance_manager_address),
        balance_manager_bound,
        pools,
        reservations: vec_map::empty(),
        nonce: 0,
    };

    activity_log::emit_policy_created(policy_id, owner, agent, now_ms);
    transfer::share_object(policy);
}

/// Bind the DeepBook BalanceManager to a policy that was created without one.
/// Owner-only and one-shot: once bound, the funding path is immutable.
public fun set_balance_manager(
    policy: &mut AgentPolicy,
    balance_manager_address: address,
    clock: &Clock,
    ctx: &TxContext,
) {
    assert_owner(policy, ctx);
    assert!(policy.status != STATUS_REVOKED, E_REVOKED);
    assert!(!policy.balance_manager_bound, E_BALANCE_MANAGER_ALREADY_SET);
    policy.balance_manager_id = object::id_from_address(balance_manager_address);
    policy.balance_manager_bound = true;
    activity_log::emit_policy_unpaused(id(policy), policy.owner, policy.agent, clock.timestamp_ms());
}

public fun pause_policy(policy: &mut AgentPolicy, clock: &Clock, ctx: &TxContext) {
    assert_owner(policy, ctx);
    assert!(policy.status != STATUS_REVOKED, E_REVOKED);
    policy.status = STATUS_PAUSED;
    activity_log::emit_policy_paused(id(policy), policy.owner, policy.agent, clock.timestamp_ms());
}

public fun unpause_policy(policy: &mut AgentPolicy, clock: &Clock, ctx: &TxContext) {
    assert_owner(policy, ctx);
    assert!(policy.status != STATUS_REVOKED, E_REVOKED);
    policy.status = STATUS_ACTIVE;
    activity_log::emit_policy_unpaused(id(policy), policy.owner, policy.agent, clock.timestamp_ms());
}

public fun revoke_policy(policy: &mut AgentPolicy, clock: &Clock, ctx: &TxContext) {
    assert_owner(policy, ctx);
    policy.status = STATUS_REVOKED;
    activity_log::emit_policy_revoked(id(policy), policy.owner, policy.agent, clock.timestamp_ms());
}

/// Validate an order against the policy and reserve `amount` quote units
/// against both the global and per-pool budgets. The reservation is keyed by
/// `order_id` so `release_reservation` can refund the exact amount on cancel.
///
/// `amount` MUST be derived on-chain from the executed order parameters
/// (price * quantity), never supplied independently by the agent — see
/// `deepbook_adapter::place_limit_order_with_policy`.
public(package) fun validate_and_consume(
    policy: &mut AgentPolicy,
    pool_id: ID,
    balance_manager_id: ID,
    order_id: u128,
    amount: u64,
    max_slippage_bps: u64,
    clock: &Clock,
    ctx: &TxContext,
) {
    assert!(ctx.sender() == policy.agent, E_NOT_AGENT);
    assert!(policy.status == STATUS_ACTIVE, E_POLICY_NOT_ACTIVE);
    assert!(clock.timestamp_ms() < policy.expires_at_ms, E_POLICY_EXPIRED);
    assert!(policy.balance_manager_bound, E_BALANCE_MANAGER_MISMATCH);
    assert!(balance_manager_id == policy.balance_manager_id, E_BALANCE_MANAGER_MISMATCH);
    assert!(amount <= policy.max_per_order, E_ORDER_TOO_LARGE);
    assert!(max_slippage_bps <= policy.max_slippage_bps, E_SLIPPAGE_EXCEEDED);
    budget::assert_budget_available(policy.spent_budget, policy.global_budget, amount, E_BUDGET_EXCEEDED);

    let len = policy.pools.length();
    let mut i = 0;
    let mut found = false;
    while (i < len) {
        let pool = &mut policy.pools[i];
        if (pool.enabled && pool.pool_id == pool_id) {
            assert!(amount <= pool.max_order_size, E_ORDER_TOO_LARGE);
            assert!(max_slippage_bps <= pool.max_slippage_bps, E_SLIPPAGE_EXCEEDED);
            budget::assert_budget_available(pool.spent_quote, pool.max_quote_budget, amount, E_BUDGET_EXCEEDED);
            pool.spent_quote = pool.spent_quote + amount;
            found = true;
            break
        };
        i = i + 1;
    };
    assert!(found, E_POOL_NOT_ALLOWED);

    policy.spent_budget = policy.spent_budget + amount;
    policy.nonce = policy.nonce + 1;

    // Record the reservation so a later cancel can release it exactly.
    if (policy.reservations.contains(&order_id)) {
        let existing = &mut policy.reservations[&order_id];
        existing.amount = existing.amount + amount;
    } else {
        policy.reservations.insert(order_id, Reservation { pool_id, amount });
    }
}

/// Release a previously reserved amount (e.g. on order cancel), refunding both
/// global and per-pool spent counters. Caller must be the agent. Releasing the
/// full reservation on a partially-filled-then-cancelled order slightly
/// over-refunds the policy cap, but never affects custodied funds (the
/// BalanceManager holds real balances independently).
public(package) fun release_reservation(
    policy: &mut AgentPolicy,
    order_id: u128,
    clock: &Clock,
    ctx: &TxContext,
) {
    assert!(ctx.sender() == policy.agent, E_NOT_AGENT);
    assert!(clock.timestamp_ms() < policy.expires_at_ms, E_POLICY_EXPIRED);
    assert!(policy.reservations.contains(&order_id), E_UNKNOWN_RESERVATION);

    let (_, reservation) = policy.reservations.remove(&order_id);
    let Reservation { pool_id, amount } = reservation;

    if (policy.spent_budget >= amount) {
        policy.spent_budget = policy.spent_budget - amount;
    } else {
        policy.spent_budget = 0;
    };

    let len = policy.pools.length();
    let mut i = 0;
    while (i < len) {
        let pool = &mut policy.pools[i];
        if (pool.pool_id == pool_id) {
            if (pool.spent_quote >= amount) {
                pool.spent_quote = pool.spent_quote - amount;
            } else {
                pool.spent_quote = 0;
            };
            break
        };
        i = i + 1;
    };
}

/// Validate (without consuming budget) that the agent may act on this pool.
public(package) fun validate_action(
    policy: &AgentPolicy,
    pool_id: ID,
    balance_manager_id: ID,
    clock: &Clock,
    ctx: &TxContext,
) {
    assert!(ctx.sender() == policy.agent, E_NOT_AGENT);
    assert!(policy.status == STATUS_ACTIVE, E_POLICY_NOT_ACTIVE);
    assert!(clock.timestamp_ms() < policy.expires_at_ms, E_POLICY_EXPIRED);
    assert!(policy.balance_manager_bound, E_BALANCE_MANAGER_MISMATCH);
    assert!(balance_manager_id == policy.balance_manager_id, E_BALANCE_MANAGER_MISMATCH);

    let len = policy.pools.length();
    let mut i = 0;
    let mut found = false;
    while (i < len) {
        let pool = &policy.pools[i];
        if (pool.enabled && pool.pool_id == pool_id) {
            found = true;
            break
        };
        i = i + 1;
    };
    assert!(found, E_POOL_NOT_ALLOWED);
}

public fun id(policy: &AgentPolicy): ID {
    object::id(policy)
}

public fun owner(policy: &AgentPolicy): address {
    policy.owner
}

public fun agent(policy: &AgentPolicy): address {
    policy.agent
}

#[test_only]
public fun new_for_testing(
    owner: address,
    agent: address,
    status: u8,
    expires_at_ms: u64,
    global_budget: u64,
    spent_budget: u64,
    max_per_order: u64,
    max_slippage_bps: u64,
    pool_address: address,
    pool_budget: u64,
    pool_spent: u64,
    pool_max_order_size: u64,
    pool_max_slippage_bps: u64,
    balance_manager_address: address,
    ctx: &mut TxContext,
): AgentPolicy {
    AgentPolicy {
        id: object::new(ctx),
        owner,
        agent,
        status,
        created_at_ms: 0,
        expires_at_ms,
        global_budget,
        spent_budget,
        max_per_order,
        max_slippage_bps,
        balance_manager_id: object::id_from_address(balance_manager_address),
        balance_manager_bound: balance_manager_address != UNSET_ADDRESS,
        pools: vector[
            PoolRule {
                pool_id: object::id_from_address(pool_address),
                max_quote_budget: pool_budget,
                spent_quote: pool_spent,
                max_order_size: pool_max_order_size,
                max_slippage_bps: pool_max_slippage_bps,
                enabled: true,
            },
        ],
        reservations: vec_map::empty(),
        nonce: 0,
    }
}

#[test_only]
public fun validate_and_consume_for_testing(
    policy: &mut AgentPolicy,
    pool_id: ID,
    balance_manager_id: ID,
    order_id: u128,
    amount: u64,
    max_slippage_bps: u64,
    clock: &Clock,
    ctx: &TxContext,
) {
    validate_and_consume(policy, pool_id, balance_manager_id, order_id, amount, max_slippage_bps, clock, ctx);
}

#[test_only]
public fun release_reservation_for_testing(
    policy: &mut AgentPolicy,
    order_id: u128,
    clock: &Clock,
    ctx: &TxContext,
) {
    release_reservation(policy, order_id, clock, ctx);
}

#[test_only]
public fun spent_budget_for_testing(policy: &AgentPolicy): u64 {
    policy.spent_budget
}

#[test_only]
public fun nonce_for_testing(policy: &AgentPolicy): u64 {
    policy.nonce
}

#[test_only]
public fun destroy_for_testing(policy: AgentPolicy) {
    let AgentPolicy {
        id,
        owner: _,
        agent: _,
        status: _,
        created_at_ms: _,
        expires_at_ms: _,
        global_budget: _,
        spent_budget: _,
        max_per_order: _,
        max_slippage_bps: _,
        balance_manager_id: _,
        balance_manager_bound: _,
        pools: _,
        reservations: _,
        nonce: _,
    } = policy;
    id.delete();
}

fun assert_owner(policy: &AgentPolicy, ctx: &TxContext) {
    assert!(ctx.sender() == policy.owner, E_NOT_OWNER);
}
