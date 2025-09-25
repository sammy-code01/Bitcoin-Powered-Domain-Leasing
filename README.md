# Bitcoin-Powered Domain Leasing

A decentralized platform for short-term .btc domain rentals with automated lease management and escrow payments.

## Features

- **Domain Registration**: Owners can list domains with custom lease pricing
- **Flexible Leasing**: Support for various lease durations with minimum requirements
- **Automated Escrow**: Secure payment processing with automatic fund release
- **Lease Extensions**: Tenants can extend active leases seamlessly
- **Earnings Tracking**: Comprehensive revenue tracking for domain owners
- **Auto-Reclamation**: Domains automatically return to owners after lease expiry

## Contract Functions

### Public Functions
- `register-domain()`: List a domain for lease with pricing
- `lease-domain()`: Rent a domain for specified duration
- `extend-lease()`: Extend an active lease
- `reclaim-domain()`: Reclaim expired domain

### Read-Only Functions
- `get-domain-info()`: Retrieve domain registration details
- `get-lease-info()`: Get active lease information
- `is-domain-available()`: Check domain availability
- `get-earnings()`: View owner earnings

## Usage

Domain owners register their domains with lease terms, tenants pay upfront for rental periods, and the system manages the entire lease lifecycle automatically.

## Economics

Pricing is set per block, providing granular control over lease costs and enabling both short-term and long-term rental strategies.