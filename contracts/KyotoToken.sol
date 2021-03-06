pragma solidity ^0.4.0;

/**
 * https://github.com/MakerDAO/maker-otc/blob/master/contracts/simple_market.sol
 */
contract SafeMath {

  function safeMul(uint a, uint b) internal returns (uint) {
    uint c = a * b;
    assert(a == 0 || c / a == b);
    return c;
  }

  function safeSub(uint a, uint b) internal returns (uint) {
    assert(b <= a);
    return a - b;
  }

  function safeAdd(uint a, uint b) internal returns (uint) {
    uint c = a + b;
    assert(c>=a && c>=b);
    return c;
  }

  function assert(bool assertion) internal {
    if (!assertion) throw;
  }
}


/**
 * https://github.com/ethereum/EIPs/issues/20
 */
contract Token {
    /// @return total amount of tokens
    function totalSupply() constant returns (uint256 supply) {}

    /// @param _owner The address from which the balance will be retrieved
    /// @return The balance
    function balanceOf(address _owner) constant returns (uint256 balance) {}

    /// @notice send `_value` token to `_to` from `msg.sender`
    /// @param _to The address of the recipient
    /// @param _value The amount of token to be transferred
    /// @return Whether the transfer was successful or not
    function transfer(address _to, uint256 _value) returns (bool success) {}

    /// @notice send `_value` token to `_to` from `_from` on the condition it is approved by `_from`
    /// @param _from The address of the sender
    /// @param _to The address of the recipient
    /// @param _value The amount of token to be transferred
    /// @return Whether the transfer was successful or not
    function transferFrom(address _from, address _to, uint256 _value) returns (bool success) {}

    /// @notice `msg.sender` approves `_addr` to spend `_value` tokens
    /// @param _spender The address of the account able to transfer the tokens
    /// @param _value The amount of wei to be approved for transfer
    /// @return Whether the approval was successful or not
    function approve(address _spender, uint256 _value) returns (bool success) {}

    /// @param _owner The address of the account owning tokens
    /// @param _spender The address of the account able to transfer the tokens
    /// @return Amount of remaining tokens allowed to spent
    function allowance(address _owner, address _spender) constant returns (uint256 remaining) {}

    event Transfer(address indexed _from, address indexed _to, uint256 _value);
    event Approval(address indexed _owner, address indexed _spender, uint256 _value);

}

/**
 * https://github.com/ethereum/EIPs/issues/20
 */
contract StandardToken is Token {
    mapping(address => uint256) balances;
    mapping (address => mapping (address => uint256)) allowed;
    uint256 public totalSupply;

    function transfer(address _to, uint256 _value) returns (bool success) {
        //Default assumes totalSupply can't be over max (2^256 - 1).
        //If your token leaves out totalSupply and can issue more tokens as time goes on, you need to check if it doesn't wrap.
        //Replace the if with this one instead.
        if (balances[msg.sender] >= _value && balances[_to] + _value > balances[_to]) {
        //if (balances[msg.sender] >= _value && _value > 0) {
            balances[msg.sender] -= _value;
            balances[_to] += _value;
            Transfer(msg.sender, _to, _value);
            return true;
        } else { return false; }
    }

    function transferFrom(address _from, address _to, uint256 _value) returns (bool success) {
        //same as above. Replace this line with the following if you want to protect against wrapping uints.
        if (balances[_from] >= _value && allowed[_from][msg.sender] >= _value && balances[_to] + _value > balances[_to]) {
        //if (balances[_from] >= _value && allowed[_from][msg.sender] >= _value && _value > 0) {
            balances[_to] += _value;
            balances[_from] -= _value;
            allowed[_from][msg.sender] -= _value;
            Transfer(_from, _to, _value);
            return true;
        } else { return false; }
    }

    function balanceOf(address _owner) constant returns (uint256 balance) {
        return balances[_owner];
    }

    function approve(address _spender, uint256 _value) returns (bool success) {
        allowed[msg.sender][_spender] = _value;
        Approval(msg.sender, _spender, _value);
        return true;
    }

    function allowance(address _owner, address _spender) constant returns (uint256 remaining) {
      return allowed[_owner][_spender];
    }
}


 //Crowdsale contract
contract KyotoToken is StandardToken, SafeMath {
    string public name = "Kyoto";
    string public symbol = "KYOTO";
    uint public decimals = 18;

    uint public startBlock; //Start of crowdsale determined by block number
    uint public endBlock;  //End of crowdsale determined by block number

    uint public etherCap; //Crowdsale cap based on ether
    uint public minEtherToRaise; //Minimum goal of ether needed to be raised
    uint public etherRaised = 0; //Keep track of ether raised in contract
    bool public isFueled = false; //True if contract reached minimum ether goal, else false
    bool public halted = false; //Used by owner to halt crowdsale

    address public multiSig; //Multisig address used to store crowdsale funds
    address public owner; //Used for halt function
    mapping(address => uint256) weiGiven; //Tracks the amount of wei deposited from each contributor (used for refund)

    //Public events
    event LogPayOut(address indexed _recipient, uint _amount);
    event LogFuelingToDate(uint value);
    event LogCreateToken(address indexed to, uint amount);
    event LogRefund(address indexed to, uint value);

    //Contract initializer
    function Crowdsale(address _owner, address _multiSig, uint _minEtherToRaise, uint _startBlock, uint _endBlock, uint _etherCap) {
        owner = _owner;
        multiSig = _multiSig;
        startBlock = _startBlock;
        endBlock = _endBlock;
        minEtherToRaise = _minEtherToRaise;
        etherCap = _etherCap;
    }

    //Creates tokens only during crowdsale
    function createToken(address _tokenHolder) {
        //Sanity Check
        if (block.number < startBlock || block.number > endBlock || halted || safeAdd(etherRaised, msg.value) > etherCap) throw;

        //Get token amount
        uint token = safeMul(msg.value, price());

        //Add to balances
        balances[_tokenHolder] = safeAdd(balances[_tokenHolder], token);
        weiGiven[_tokenHolder] = safeAdd(weiGiven[_tokenHolder], msg.value);
        totalSupply = safeAdd(totalSupply, token);
        etherRaised = safeAdd(etherRaised, msg.value);

        //Create Event
        LogCreateToken(_tokenHolder, token);

        //Check if crowdsale is fueled
        if (etherRaised >= minEtherToRaise && isFueled == false) {
            isFueled = true;
            //Create Event
            LogFuelingToDate(totalSupply);
        }
    }

    //Returns current price of token
    function price() constant returns (uint price) {
        //Power Day
        if (block.number < startBlock + 6000) return 140;
        //First Week 7 day
        else if (block.number < startBlock + 42500) return 120;
        //Second Week 14 days
        else if (block.number < startBlock + 85000) return 110;
        //Final Week 21 days
        else if (block.number < endBlock) return 100;
    }

    //Used for refunds if crowdsale fails to reach minEtherToRaise
    function refund() {
        if (block.number < endBlock || isFueled == true) throw;

        totalSupply = safeSub(totalSupply, balances[msg.sender]);
        uint amountToWithdraw = weiGiven[msg.sender];
        balances[msg.sender] = 0;
        weiGiven[msg.sender] = 0;

        if (!msg.sender.send(amountToWithdraw)) throw;

        LogRefund(msg.sender, weiGiven[msg.sender]);
    }

    //Sends raised ether to multsig after endBlock if minEtherToRaise is reached
    function payOut(address _recipient, uint _amount) {
        if (msg.sender != owner) throw;

        if (isFueled && block.number > endBlock) {
            if (!multiSig.send(_amount)) throw;

            LogPayOut(_recipient, _amount);
        }
    }

    //Halts crowdsale
    function halt() {
        if (msg.sender != owner) throw;
        halted = true;
    }

    //Unhalts crowdsale
    function unhalt() {
        if (msg.sender != owner) throw;
        halted = false;
    }

    //Prevents tokens transfer before crowdsale ends
    function transfer(address _to, uint256 _value) returns (bool success) {
        if (isFueled && block.number > endBlock) {
            return super.transfer(_to, _value);
        }
    }

    //Prevents tokens transfer before crowdsale ends
    function transferFrom(address _from, address _to, uint256 _value) returns (bool success) {
        if (isFueled && block.number > endBlock) {
            return super.transferFrom(_from, _to, _value);
        }
    }

    //Default function used to create tokens
    function () payable {
        createToken(msg.sender);
    }
}
