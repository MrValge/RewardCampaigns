// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;


import "IERC20.sol";
import "Context.sol";
import "SafeMath.sol";
import "AccessControl.sol";

 contract PaymentContract is Context, AccessControl {
  using SafeMath for uint256;

  mapping(address => IERC20) internal token;
  mapping(address => uint256) internal campaignTokenBalance;
  mapping(address => uint256) internal totalRewardsClaimed;

  address internal nativeToken;

  // Campaign data structure
  struct campaignData {
    address paymentToken;
    uint256 balance;
    uint256 minReward;
    uint256 totalAllowance;
  }

  mapping(bytes32 => campaignData) internal campaign; // Campaign struct mapping by campaign ID
  mapping(bytes32 => bool) internal isActiveCampaign; // Active/Inactive campaign boolean
  mapping(bytes32 => mapping(address => uint256)) allowance; // Reward allowance for wallet address mapped to campaign ID

// Setting up admin role and native token address to 0-address for ease of use through functions
  constructor()
  {
    _setupRole(DEFAULT_ADMIN_ROLE, _msgSender());
    nativeToken = address(0);
    token[nativeToken] = IERC20(nativeToken);
  }

// Function to create campaign with a specific token reward
  function createCampaign(bytes32 _campaignID, address _token, uint256 _amount, uint256 _minReward)
  external
  payable
  {
    require(!isActiveCampaign[_campaignID], "[CampaignID already active]");
    require(isPaymentToken(_token), "[Token not supported]");
    if(_token == nativeToken) require(msg.value == _amount, "[Mismatch of input value and sent value]");
    else
    {
      require(token[_token].allowance(_msgSender(), address(this)) >= _amount, "[Insufficient allowance to contract]");
      require(token[_token].transferFrom(_msgSender(), address(this), _amount), "[Token transfer error]");
    }
    campaign[_campaignID] = campaignData(_token, _amount, _minReward, 0);
    campaignTokenBalance[_token] = campaignTokenBalance[_token].add(_amount);
    isActiveCampaign[_campaignID] = true;
  }

// Function to remove a campaign. Remaining token balance credited to smart contract address.
  function removeCampaign(bytes32 _campaignID)
  public
  {
    require(hasRole(DEFAULT_ADMIN_ROLE, _msgSender()) || (_msgSender() == address(this)), "[Call not admin or internal]");
    isActiveCampaign[_campaignID] = false;
    campaignTokenBalance[campaign[_campaignID].paymentToken] = campaignTokenBalance[campaign[_campaignID].paymentToken].sub(campaign[_campaignID].balance);
  }

// Function to claim allocated reward from a campaign. If remaining balance for campaign is under minReward, campaign is removed.
  function claimReward(bytes32 _campaignID)
  external
  {
    require(isActiveCampaign[_campaignID], "[Campaign not active]");
    require(allowance[_campaignID][_msgSender()] > 0, "[No rewards allocated to this address]");
    require(campaign[_campaignID].balance >= allowance[_campaignID][_msgSender()], "[Reward pool depleted, contact support]");
    uint256 amount = allowanceOf(_campaignID, _msgSender());
    allowance[_campaignID][_msgSender()] = 0;
    campaign[_campaignID].totalAllowance = campaign[_campaignID].totalAllowance.sub(amount);
    campaign[_campaignID].balance = campaign[_campaignID].balance.sub(amount);
    if(campaign[_campaignID].paymentToken == nativeToken)
    {
      (bool sent,) = _msgSender().call{value: amount}("");
      require(sent, "[Failed to send native]");
    }
    else
    {
      require(token[campaign[_campaignID].paymentToken].transferFrom(address(this), _msgSender(), amount), "[Token claim unsuccessful, contact support]");
    }

    campaignTokenBalance[campaign[_campaignID].paymentToken] = campaignTokenBalance[campaign[_campaignID].paymentToken].sub(amount);
    totalRewardsClaimed[campaign[_campaignID].paymentToken] = totalRewardsClaimed[campaign[_campaignID].paymentToken].add(amount);
    if(campaign[_campaignID].balance < campaign[_campaignID].minReward) removeCampaign(_campaignID);
  }

// Function to set campaign reward allowance for a specific wallet address
  function setCampaignAllowance(bytes32 _campaignID, address _address, uint256 _allowance)
  external
  {
    require(hasRole(DEFAULT_ADMIN_ROLE, _msgSender()), "[Admin role required]");
    require(isActiveCampaign[_campaignID], "[Campaign inactive]");
    require(campaign[_campaignID].totalAllowance.add(_allowance) <= campaign[_campaignID].balance, "[Allowance exceeds balance]");
    allowance[_campaignID][_address] = _allowance;
    campaign[_campaignID].totalAllowance = campaign[_campaignID].totalAllowance.add(_allowance);
  }

// Function to set campaign reward allowances for a batch of wallets
  function setCampaignBatchAllowance(bytes32 _campaignID, address[] memory _address, uint256[] memory _allowance)
  external
  {
    require(hasRole(DEFAULT_ADMIN_ROLE, _msgSender()), "[Admin role required]");
    require(isActiveCampaign[_campaignID], "[Campaign inactive]");
    for (uint256 s = 0; s < _address.length; s += 1)
    {
      allowance[_campaignID][_address[s]] = _allowance[s];
      campaign[_campaignID].totalAllowance = campaign[_campaignID].totalAllowance.add(_allowance[s]);
    }
    require(campaign[_campaignID].totalAllowance <= campaign[_campaignID].balance, "[Allowance exceeds balance]");

  }

// Function to view the campaign reward allowance of a wallet
  function allowanceOf(bytes32 _campaignID, address _address)
  public
  view
  returns(uint256)
  {
    return allowance[_campaignID][_address];
  }

// Function to view campaign's token of payment, token balance and allocated rewards
  function getCampaignData(bytes32 _campaignID)
  external
  view
  returns(address, uint256, uint256)
  {
    return(campaign[_campaignID].paymentToken, campaign[_campaignID].balance, campaign[_campaignID].totalAllowance);
  }

// Function to add a new token for use in the system
  function addPaymentToken(address _token)
  external
  {
    require(hasRole(DEFAULT_ADMIN_ROLE, _msgSender()), "[Admin role required]");
    require(!isPaymentToken(_token), "[Token already accepted]");
    token[_token] = IERC20(_token);
  }

// Function to check if a token is supported in the system
  function isPaymentToken(address _token)
  public
  view
  returns(bool)
  {
    if (_token == address(token[_token])) return (true);
    return (false);
  }

// Function to withdraw any token balance left over from finished campaigns
  function withdraw(address _token, uint256 _amount, address payable _recipient)
  external
  {
    require(hasRole(DEFAULT_ADMIN_ROLE, _msgSender()), "[Admin role required]");

    if(_token == nativeToken)
    {
      require(address(this).balance.sub(campaignTokenBalance[_token]) >= _amount, "[Amount exceeds available balance]");
      (bool sent,) = _recipient.call{value: _amount}("");
      require(sent, "[Failed to send native]");
    }
    else
    {
      require(token[_token].balanceOf(address(this)).sub(campaignTokenBalance[_token]) >= _amount, "[Amount exceeds available balance]");
      require(token[_token].transferFrom(address(this), _recipient, _amount), "[Token claim unsuccessful, contact support]");
    }
  }

  receive() external payable {}
}
