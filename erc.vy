# EVENTS

event Transfer:
    sender: indexed(address)
    receiver: indexed(address)
    value: uint256

event Approval:
    owner: indexed(address)
    spender: indexed(address)
    value: uint256

event DividendDeposited:
    amount: uint256

event DividendClaimed:
    holder: indexed(address)
    amount: uint256

event ProposalCreated:
    id: uint256
    description: String[128]

event Voted:
    voter: indexed(address)
    proposal_id: uint256
    weight: uint256

event ProposalExecuted:
    id: uint256


# STORAGE


name: public(String[64])
symbol: public(String[32])
decimals: public(uint256)

owner: public(address)

total_supply: public(uint256)
balances: HashMap[address, uint256]
allowances: HashMap[address, HashMap[address, uint256]]

# Whitelist
whitelisted: public(HashMap[address, bool])

# Dividend accounting
dividend_per_token: uint256
claimed_dividend: HashMap[address, uint256]

# Governance
struct Proposal:
    description: String[128]
    vote_count: uint256
    executed: bool

proposal_count: public(uint256)
proposals: HashMap[uint256, Proposal]
has_voted: HashMap[uint256, HashMap[address, bool]]

# CONSTRUCTOR

@external
def __init__(
    _name: String[64],
    _symbol: String[32],
    _decimals: uint256,
    _initial_supply: uint256
):
    self.owner = msg.sender
    self.name = _name
    self.symbol = _symbol
    self.decimals = _decimals

    self.total_supply = _initial_supply
    self.balances[msg.sender] = _initial_supply
    self.whitelisted[msg.sender] = True

    log Transfer(ZERO_ADDRESS, msg.sender, _initial_supply)


# WHITELIST MANAGEMENT

@external
def add_to_whitelist(_addr: address):
    assert msg.sender == self.owner
    self.whitelisted[_addr] = True


@external
def remove_from_whitelist(_addr: address):
    assert msg.sender == self.owner
    self.whitelisted[_addr] = False

# ERC20 

@external
def transfer(_to: address, _value: uint256) -> bool:
    assert self.whitelisted[msg.sender], "Sender not whitelisted"
    assert self.whitelisted[_to], "Receiver not whitelisted"
    assert self.balances[msg.sender] >= _value

    self._claim_dividend(msg.sender)
    self._claim_dividend(_to)

    self.balances[msg.sender] -= _value
    self.balances[_to] += _value

    log Transfer(msg.sender, _to, _value)
    return True


@external
def approve(_spender: address, _value: uint256) -> bool:
    self.allowances[msg.sender][_spender] = _value
    log Approval(msg.sender, _spender, _value)
    return True


@external
def transferFrom(_from: address, _to: address, _value: uint256) -> bool:
    assert self.whitelisted[_from]
    assert self.whitelisted[_to]
    assert self.balances[_from] >= _value
    assert self.allowances[_from][msg.sender] >= _value

    self._claim_dividend(_from)
    self._claim_dividend(_to)

    self.allowances[_from][msg.sender] -= _value
    self.balances[_from] -= _value
    self.balances[_to] += _value

    log Transfer(_from, _to, _value)
    return True


@external
@view
def balanceOf(_owner: address) -> uint256:
    return self.balances[_owner]

# DIVIDEND / COUPON LOGIC

@external
@payable
def deposit_dividend():
    assert msg.sender == self.owner
    assert self.total_supply > 0

    self.dividend_per_token += msg.value / self.total_supply
    log DividendDeposited(msg.value)


@internal
def _claim_dividend(_holder: address):
    owed: uint256 = (
        self.balances[_holder] * self.dividend_per_token
        - self.claimed_dividend[_holder]
    )

    if owed > 0:
        self.claimed_dividend[_holder] += owed
        send(_holder, owed)
        log DividendClaimed(_holder, owed)


@external
def claim_dividend():
    self._claim_dividend(msg.sender)

# GOVERNANCE

@external
def create_proposal(_description: String[128]):
    assert self.balances[msg.sender] > 0

    pid: uint256 = self.proposal_count
    self.proposals[pid] = Proposal({
        description: _description,
        vote_count: 0,
        executed: False
    })

    self.proposal_count += 1
    log ProposalCreated(pid, _description)


@external
def vote(_proposal_id: uint256):
    assert not self.has_voted[_proposal_id][msg.sender]
    assert self.balances[msg.sender] > 0

    weight: uint256 = self.balances[msg.sender]

    self.proposals[_proposal_id].vote_count += weight
    self.has_voted[_proposal_id][msg.sender] = True

    log Voted(msg.sender, _proposal_id, weight)


@external
def execute_proposal(_proposal_id: uint256):
    assert msg.sender == self.owner
    assert not self.proposals[_proposal_id].executed

    assert self.proposals[_proposal_id].vote_count > (
        self.total_supply / 2
    )

    self.proposals[_proposal_id].executed = True
    log ProposalExecuted(_proposal_id)
