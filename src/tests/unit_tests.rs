use crate::vm::BulkBookVM;
use crate::instructions::Instruction;
use crate::orderbook::ShardedOrderbook;
use std::sync::atomic::Ordering;

#[test]
fn test_place_order() {
    let mut orderbook = ShardedOrderbook::new(8);
    orderbook.place_order(100, 10, 1);
    assert_eq!(orderbook.shards[orderbook.price_to_shard(100)].len(), 1);
    println!("test_place_order passed");
}

#[test]
fn test_vm_place_order() {
    let program = vec![
        Instruction::Load(0, 100),  // Price
        Instruction::Load(1, 10),   // Amount
        Instruction::Load(2, 1),    // ID
        Instruction::PlaceOrderOptimized(0, 1, 2),
    ];
    let mut vm = BulkBookVM::new(program, 8);
    
    println!("Initial state:");
    println!("Registers: {:?}", vm.registers);
    println!("Best bid: {}", vm.best_bid.load(Ordering::Relaxed));
    println!("Best ask: {}", vm.best_ask.load(Ordering::Relaxed));

    vm.run();

    println!("\nFinal state:");
    println!("Registers: {:?}", vm.registers);
    println!("Best bid: {}", vm.best_bid.load(Ordering::Relaxed));
    println!("Best ask: {}", vm.best_ask.load(Ordering::Relaxed));
    
    let shard = vm.orderbook.price_to_shard(100);
    println!("Orders in shard {}: {}", shard, vm.orderbook.shards[shard].len());

    assert_eq!(vm.best_bid.load(Ordering::Relaxed), 100);
    assert_eq!(vm.orderbook.shards[vm.orderbook.price_to_shard(100)].len(), 1);
    println!("test_vm_place_order passed");
}

#[test]
fn test_vectorized_price_check() {
    let program = vec![
        Instruction::Load(0, 90),  // start price
        Instruction::Load(1, 110), // end price
        Instruction::Load(2, 0),   // result register
        Instruction::Load(3, 0),   // shard
        Instruction::VectorizedPriceCheck(0, 1, 2, 3),
    ];
    let mut vm = BulkBookVM::new(program, 8);
    
    // Place some orders
    vm.orderbook.place_order(95, 5, 1);
    vm.orderbook.place_order(100, 10, 2);
    vm.orderbook.place_order(105, 15, 3);

    vm.run();

    assert_eq!(vm.registers[2], 30); // 5 + 10 + 15
}

#[test]
fn test_update_best_bid_ask() {
    let program = vec![
        Instruction::Load(0, 100), // price
        Instruction::Load(1, 10),  // amount
        Instruction::Load(2, 1),   // id
        Instruction::PlaceOrderOptimized(0, 1, 2),
        Instruction::Load(0, 105), // price
        Instruction::Load(1, 5),   // amount
        Instruction::Load(2, 2),   // id
        Instruction::PlaceOrderOptimized(0, 1, 2),
        Instruction::UpdateBestBidAsk,
    ];
    let mut vm = BulkBookVM::new(program, 8);
    vm.run();

    assert_eq!(vm.best_bid.load(Ordering::Relaxed), 105);
    assert_eq!(vm.best_ask.load(Ordering::Relaxed), 100);
}