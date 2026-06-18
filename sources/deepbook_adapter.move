module sentinel::deepbook_adapter;

use sentinel::{activity_log, agent_policy::{Self, AgentPolicy}};
use deepbook::{
    balance_manager::{BalanceManager, TradeProof},
    math,
    pool::Pool,
};
use sui::clock::{Self, Clock};

/// Place a DeepBook limit order through the policy. The quote amount consumed
/// against the budget is derived ON-CHAIN from the exact `price` and `quantity`
/// passed to `pool::place_limit_order` (`math::mul(quantity, price)`), so the
/// agent cannot decouple the budgeted amount from the executed order. Budget
/// validation, the real order, the reservation, and the activity event all
/// happen atomically in this one call.
public fun place_limit_order_with_policy<BaseAsset, QuoteAsset>(
    policy: &mut AgentPolicy,
    pool: &mut Pool<BaseAsset, QuoteAsset>,
    balance_manager: &mut BalanceManager,
    trade_proof: &TradeProof,
    client_order_id: u64,
    order_type: u8,
    self_matching_option: u8,
    price: u64,
    quantity: u64,
    is_bid: bool,
    pay_with_deep: bool,
    expire_timestamp: u64,
    max_slippage_bps: u64,
    // Deterministic off-chain risk attestation, recorded on-chain with the order.
    // Attestation only: the hard ceiling is enforced by `validate_and_consume`.
    risk_score: u64,
    reason_code: vector<u8>,
    clock: &Clock,
    ctx: &TxContext,
) {
    // Quote units committed by this order, computed the same way DeepBook does.
    let quote_amount = math::mul(quantity, price);
    let pool_id = object::id(pool);
    let balance_manager_id = object::id(balance_manager);

    agent_policy::validate_and_consume(
        policy,
        pool_id,
        balance_manager_id,
        (client_order_id as u128),
        quote_amount,
        max_slippage_bps,
        clock,
        ctx,
    );

    let order_info = pool.place_limit_order<BaseAsset, QuoteAsset>(
        balance_manager,
        trade_proof,
        client_order_id,
        order_type,
        self_matching_option,
        price,
        quantity,
        is_bid,
        pay_with_deep,
        expire_timestamp,
        clock,
        ctx,
    );

    activity_log::emit_order_placed(
        agent_policy::id(policy),
        agent_policy::owner(policy),
        agent_policy::agent(policy),
        pool_id,
        order_info.order_id(),
        quote_amount,
        price,
        risk_score,
        reason_code,
        clock.timestamp_ms(),
    );
}

/// Cancel a DeepBook order through the policy and release its budget
/// reservation atomically.
public fun cancel_order_with_policy<BaseAsset, QuoteAsset>(
    policy: &mut AgentPolicy,
    pool: &mut Pool<BaseAsset, QuoteAsset>,
    balance_manager: &mut BalanceManager,
    trade_proof: &TradeProof,
    order_id: u128,
    clock: &Clock,
    ctx: &TxContext,
) {
    let pool_id = object::id(pool);

    pool.cancel_order<BaseAsset, QuoteAsset>(
        balance_manager,
        trade_proof,
        order_id,
        clock,
        ctx,
    );

    agent_policy::release_reservation(policy, order_id, clock, ctx);

    activity_log::emit_order_cancelled(
        agent_policy::id(policy),
        agent_policy::owner(policy),
        agent_policy::agent(policy),
        pool_id,
        order_id,
        clock.timestamp_ms(),
    );
}

/// Modify (reduce) the quantity of an existing DeepBook order through the
/// policy. DeepBook only allows shrinking an order, so the committed quote can
/// only decrease; we conservatively leave the original reservation in place
/// (over-reserving against the cap, never under). Use `cancel_order_with_policy`
/// to fully release the reservation.
public fun modify_order_with_policy<BaseAsset, QuoteAsset>(
    policy: &mut AgentPolicy,
    pool: &mut Pool<BaseAsset, QuoteAsset>,
    balance_manager: &mut BalanceManager,
    trade_proof: &TradeProof,
    order_id: u128,
    new_quantity: u64,
    clock: &Clock,
    ctx: &TxContext,
) {
    let pool_id = object::id(pool);
    let balance_manager_id = object::id(balance_manager);

    agent_policy::validate_action(policy, pool_id, balance_manager_id, clock, ctx);

    pool.modify_order<BaseAsset, QuoteAsset>(
        balance_manager,
        trade_proof,
        order_id,
        new_quantity,
        clock,
        ctx,
    );

    activity_log::emit_order_modified(
        agent_policy::id(policy),
        agent_policy::owner(policy),
        agent_policy::agent(policy),
        pool_id,
        order_id,
        new_quantity,
        clock.timestamp_ms(),
    );
}
