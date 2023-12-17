// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

contract Ownable {
    address private _owner;

    event OwnershipTransferred(
        address indexed previousOwner,
        address indexed newOwner
    );

    constructor() {
        _owner = msg.sender;
        emit OwnershipTransferred(address(0), msg.sender);
    }

    modifier onlyOwner() {
        require(isOwner(), "Caller is not the owner");
        _;
    }

    function isOwner() public view returns (bool) {
        return msg.sender == _owner;
    }

    function transferOwnership(address newOwner) public onlyOwner {
        require(newOwner != address(0), "New owner is the zero address");
        emit OwnershipTransferred(_owner, newOwner);
        _owner = newOwner;
    }
}

contract AntiFrontRunning is Ownable {
    struct Transaction {
        bytes data;
        uint256 timestamp;
        address sender;
        bool executed;
        uint256 priority; // New field for queue prioritization
    }

    uint256 public constant TIME_LOCK_DELAY = 1 hours;
    uint256 public maxGasPrice = 100 gwei;
    bool private locked;
    bool public stopped = false;

    modifier noReentrant() {
        require(!locked, "No reentrancy");
        locked = true;
        _;
        locked = false;
    }

    modifier stopInEmergency() {
        require(!stopped, "Contract is stopped");
        _;
    }

    function setMaxGasPrice(uint256 _maxGasPrice) public onlyOwner {
        maxGasPrice = _maxGasPrice;
    }

    function toggleContractActive() public onlyOwner {
        stopped = !stopped;
    }

    Transaction[] public transactionQueue;

    // Commit a transaction to the queue
    function commitTransaction(bytes memory data, uint256 priority) public {
        require(tx.gasprice <= maxGasPrice, "Gas price exceeds limit");
        Transaction memory newTx = Transaction({
            data: data,
            timestamp: block.timestamp + TIME_LOCK_DELAY,
            sender: msg.sender,
            executed: false,
            priority: priority
        });
        transactionQueue.push(newTx);
    }

    function sortTransactionQueue() private {
        // Simple insertion sort implementation
        for (uint256 i = 1; i < transactionQueue.length; i++) {
            Transaction memory key = transactionQueue[i];
            uint256 j = i - 1;
            while (
                int256(j) >= 0 && transactionQueue[j].priority > key.priority
            ) {
                transactionQueue[j + 1] = transactionQueue[j];
                j--;
            }
            transactionQueue[j + 1] = key;
        }
    }

    function executeBatchTransactions(uint256[] memory indices)
        public
        noReentrant
        stopInEmergency
    {
        for (uint256 i = 0; i < indices.length; i++) {
            uint256 index = indices[i];
            // Call executeTransaction for each index
            executeTransaction(index);
        }
    }

    // Execute transaction after time lock delay
    function executeTransaction(uint256 index)
        public
        noReentrant
        stopInEmergency
    {
        require(index < transactionQueue.length, "Invalid transaction index");
        Transaction storage txToExecute = transactionQueue[index];
        require(!txToExecute.executed, "Transaction already executed");
        require(
            block.timestamp >= txToExecute.timestamp,
            "Transaction is still locked"
        );
        require(
            txToExecute.sender == msg.sender,
            "Only sender can execute the transaction"
        );
        sortTransactionQueue();
        // Execute the transaction
        (bool success, ) = address(this).call(txToExecute.data);
        require(success, "Transaction execution failed");

        txToExecute.executed = true;
    }

    // View pending transactions
    function viewPendingTransactions()
        public
        view
        returns (Transaction[] memory)
    {
        uint256 count;
        for (uint256 i = 0; i < transactionQueue.length; i++) {
            if (!transactionQueue[i].executed) {
                count++;
            }
        }

        Transaction[] memory pendingTxs = new Transaction[](count);
        uint256 j;

        for (uint256 i = 0; i < transactionQueue.length; i++) {
            if (!transactionQueue[i].executed) {
                pendingTxs[j] = transactionQueue[i];
                j++;
            }
        }

        return pendingTxs;
    }

    // Cancel transaction
    function cancelTransaction(uint256 index) public {
        require(index < transactionQueue.length, "Invalid transaction index");
        Transaction storage txToCancel = transactionQueue[index];

        require(!txToCancel.executed, "Transaction already executed");
        require(
            txToCancel.sender == msg.sender,
            "Only sender can cancel the transaction"
        );

        txToCancel.executed = true;
    }
}
