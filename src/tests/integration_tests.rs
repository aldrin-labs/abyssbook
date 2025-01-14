use crate::vm::BulkBookVM;
use crate::instructions::Instruction;
use std::sync::atomic::Ordering;

#[test]
fn test_order_book_simulation() {
    let program = vec![
        Instruction::Load(0, 100), // price
        Instruction::Load(1, 10),  // amount
        Instruction::Load(2, 1),   // id
        Instruction::PlaceOrderOptimized(0, 1, 2),
        Instruction::Load(0, 101), // price
        Instruction::Load(1, 5),   // amount
        Instruction::Load(2, 2),   // id
        Instruction::PlaceOrderOptimized(0, 1, 2),
        Instruction::Load(3, 0),   // shard id
        Instruction::MatchOrdersInShard(3),
        Instruction::UpdateBestBidAsk,
        Instruction::Load(4, 90),  // start price
        Instruction::Load(5, 110), // end price
        Instruction::Load(6, 0),   // result register
        Instruction::Load(7, 0),   // shard
        Instruction::VectorizedPriceCheck(4, 5, 6, 7),
    ];

    let mut vm = BulkBookVM::new(program, 8);
    vm.run();

    assert_eq!(vm.best_bid.load(Ordering::Relaxed), 101);
    assert_eq!(vm.best_ask.load(Ordering::Relaxed), 100);
    assert_eq!(vm.registers[6], 15); // Total amount in the price range
}

#[test]
fn test_cross_shard_matching() {
    let program = vec![
        Instruction::Load(0, 100), // price
        Instruction::Load(1, 10),  // amount
        Instruction::Load(2, 1),   // id
        Instruction::PlaceOrderOptimized(0, 1, 2),
        Instruction::Load(0, 200), // price
        Instruction::Load(1, 5),   // amount
        Instruction::Load(2, 2),   // id
        Instruction::PlaceOrderOptimized(0, 1, 2),
        Instruction::Load(3, 0),   // shard1
        Instruction::Load(4, 1),   // shard2
        Instruction::CrossShardMatch(3, 4),
        Instruction::UpdateBestBidAsk,
    ];

    let mut vm = BulkBookVM::new(program, 8);
    vm.run();

    assert_eq!(vm.best_bid.load(Ordering::Relaxed), 200);
    assert_eq!(vm.best_ask.load(Ordering::Relaxed), 100);
}