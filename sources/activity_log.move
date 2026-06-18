module sentinel::activity_log;

use sui::event;

public struct PolicyCreated has copy, drop, store {
    policy_id: ID,
    owner: address,
    agent: address,
    protocol: vector<u8>,
    timestamp_ms: u64,
}

public struct AgentAuthorized has copy, drop, store {
    policy_id: ID,
    owner: address,
    agent: address,
    protocol: vector<u8>,
    timestamp_ms: u64,
}

public struct PolicyPaused has copy, drop, store {
    policy_id: ID,
    owner: address,
    agent: address,
    protocol: vector<u8>,
    timestamp_ms: u64,
}

public struct PolicyUnpaused has copy, drop, store {
    policy_id: ID,
    owner: address,
    agent: address,
    protocol: vector<u8>,
    timestamp_ms: u64,
}

public struct PolicyRevoked has copy, drop, store {
    policy_id: ID,
    owner: address,
    agent: address,
    protocol: vector<u8>,
    timestamp_ms: u64,
}

public struct OrderPlaced has copy, drop, store {
    policy_id: ID,
    owner: address,
    agent: address,
    protocol: vector<u8>,
    pool_id: ID,
    order_id: u128,
    action_type: vector<u8>,
    amount: u64,
    price: u64,
    risk_score: u64,
    reason_code: vector<u8>,
    timestamp_ms: u64,
}

public struct OrderCancelled has copy, drop, store {
    policy_id: ID,
    owner: address,
    agent: address,
    protocol: vector<u8>,
    pool_id: ID,
    order_id: u128,
    timestamp_ms: u64,
}

public struct OrderModified has copy, drop, store {
    policy_id: ID,
    owner: address,
    agent: address,
    protocol: vector<u8>,
    pool_id: ID,
    order_id: u128,
    new_quantity: u64,
    timestamp_ms: u64,
}

public struct BudgetConsumed has copy, drop, store {
    policy_id: ID,
    owner: address,
    agent: address,
    protocol: vector<u8>,
    pool_id: ID,
    order_id: u128,
    action_type: vector<u8>,
    amount: u64,
    price: u64,
    risk_score: u64,
    reason_code: vector<u8>,
    timestamp_ms: u64,
}

public(package) fun emit_policy_created(
    policy_id: ID,
    owner: address,
    agent: address,
    timestamp_ms: u64,
) {
    event::emit(PolicyCreated {
        policy_id,
        owner,
        agent,
        protocol: b"deepbook",
        timestamp_ms,
    });
    event::emit(AgentAuthorized {
        policy_id,
        owner,
        agent,
        protocol: b"deepbook",
        timestamp_ms,
    });
}

public(package) fun emit_policy_paused(policy_id: ID, owner: address, agent: address, timestamp_ms: u64) {
    event::emit(PolicyPaused {
        policy_id,
        owner,
        agent,
        protocol: b"deepbook",
        timestamp_ms,
    });
}

public(package) fun emit_policy_unpaused(policy_id: ID, owner: address, agent: address, timestamp_ms: u64) {
    event::emit(PolicyUnpaused {
        policy_id,
        owner,
        agent,
        protocol: b"deepbook",
        timestamp_ms,
    });
}

public(package) fun emit_policy_revoked(policy_id: ID, owner: address, agent: address, timestamp_ms: u64) {
    event::emit(PolicyRevoked {
        policy_id,
        owner,
        agent,
        protocol: b"deepbook",
        timestamp_ms,
    });
}

public(package) fun emit_order_placed(
    policy_id: ID,
    owner: address,
    agent: address,
    pool_id: ID,
    order_id: u128,
    amount: u64,
    price: u64,
    risk_score: u64,
    reason_code: vector<u8>,
    timestamp_ms: u64,
) {
    event::emit(OrderPlaced {
        policy_id,
        owner,
        agent,
        protocol: b"deepbook",
        pool_id,
        order_id,
        action_type: b"OrderPlaced",
        amount,
        price,
        risk_score,
        reason_code,
        timestamp_ms,
    });
    event::emit(BudgetConsumed {
        policy_id,
        owner,
        agent,
        protocol: b"deepbook",
        pool_id,
        order_id,
        action_type: b"BudgetConsumed",
        amount,
        price,
        risk_score,
        reason_code,
        timestamp_ms,
    });
}

public(package) fun emit_order_cancelled(
    policy_id: ID,
    owner: address,
    agent: address,
    pool_id: ID,
    order_id: u128,
    timestamp_ms: u64,
) {
    event::emit(OrderCancelled {
        policy_id,
        owner,
        agent,
        protocol: b"deepbook",
        pool_id,
        order_id,
        timestamp_ms,
    });
}

public(package) fun emit_order_modified(
    policy_id: ID,
    owner: address,
    agent: address,
    pool_id: ID,
    order_id: u128,
    new_quantity: u64,
    timestamp_ms: u64,
) {
    event::emit(OrderModified {
        policy_id,
        owner,
        agent,
        protocol: b"deepbook",
        pool_id,
        order_id,
        new_quantity,
        timestamp_ms,
    });
}
