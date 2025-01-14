pub const Instruction = union(enum) {
    Load: struct {
        reg: u8,
        value: u64,
    },
    Add: struct {
        dest: u8,
        src1: u8,
        src2: u8,
    },
    Sub: struct {
        dest: u8,
        src1: u8,
        src2: u8,
    },
    Mul: struct {
        dest: u8,
        src1: u8,
        src2: u8,
    },
    Div: struct {
        dest: u8,
        src1: u8,
        src2: u8,
    },
    PlaceOrderOptimized: struct {
        price_reg: u8,
        amount_reg: u8,
        id_reg: u8,
    },
    MatchOrdersInShard: struct {
        shard_reg: u8,
    },
    CrossShardMatch: struct {
        shard1_reg: u8,
        shard2_reg: u8,
    },
    UpdateBestBidAsk: void,
    VectorizedPriceCheck: struct {
        start_reg: u8,
        end_reg: u8,
        result_reg: u8,
        shard_reg: u8,
    },
};