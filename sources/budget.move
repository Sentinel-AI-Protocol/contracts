module sentinel::budget;

public fun assert_budget_available(spent: u64, budget: u64, amount: u64, abort_code: u64) {
    assert!(amount <= budget, abort_code);
    assert!(spent <= budget - amount, abort_code);
}
