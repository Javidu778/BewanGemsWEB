-- ============================================
-- ENUMS
-- ============================================
create type user_role as enum ('customer', 'admin');
create type order_status as enum ('pending', 'paid', 'processing', 'shipped', 'delivered', 'cancelled', 'refunded');
create type gem_cut as enum ('round', 'oval', 'cushion', 'emerald', 'pear', 'marquise', 'princess', 'radiant', 'heart', 'trillion', 'other');
create type ticket_status as enum ('open', 'in_progress', 'resolved', 'closed');

-- ============================================
-- PROFILES (extends auth.users)
-- ============================================
create table public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  full_name text,
  phone text,
  role user_role not null default 'customer',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- Auto-create a profile row whenever someone signs up
create function public.handle_new_user()
returns trigger
language plpgsql
security definer set search_path = public
as $$
begin
  insert into public.profiles (id, full_name)
  values (new.id, new.raw_user_meta_data ->> 'full_name');
  return new;
end;
$$;

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute procedure public.handle_new_user();

-- ============================================
-- ADDRESSES
-- ============================================
create table public.addresses (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  label text,                          -- "Home", "Office"
  recipient_name text not null,
  line1 text not null,
  line2 text,
  city text not null,
  state text,
  postal_code text not null,
  country text not null,
  phone text,
  is_default boolean not null default false,
  created_at timestamptz not null default now()
);

-- ============================================
-- VENDORS
-- ============================================
create table public.vendors (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  contact_email text,
  contact_phone text,
  country text,
  notes text,
  created_at timestamptz not null default now()
);

-- ============================================
-- CATEGORIES
-- ============================================
create table public.categories (
  id uuid primary key default gen_random_uuid(),
  name text not null unique,
  slug text not null unique,
  description text,
  image_url text,
  sort_order int not null default 0
);

-- ============================================
-- PRODUCTS
-- ============================================
create table public.products (
  id uuid primary key default gen_random_uuid(),
  slug text not null unique,
  name text not null,
  description text,
  category_id uuid references public.categories(id) on delete set null,
  vendor_id uuid references public.vendors(id) on delete set null,

  -- Gemstone-specific attributes
  gem_type text,                       -- "Blue Sapphire", "Ruby"
  color text,
  carat numeric(6,2),
  cut gem_cut,
  clarity text,
  origin text,
  is_certified boolean not null default false,
  certification_lab text,
  certificate_number text,
  is_heated boolean,

  -- Commerce fields
  price numeric(10,2) not null check (price >= 0),
  compare_at_price numeric(10,2),      -- for showing a strikethrough "was" price
  stock_quantity int not null default 0 check (stock_quantity >= 0),
  sku text unique,
  is_featured boolean not null default false,
  is_active boolean not null default true,

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index idx_products_category on public.products(category_id);
create index idx_products_active on public.products(is_active) where is_active = true;
create index idx_products_featured on public.products(is_featured) where is_featured = true;

-- ============================================
-- PRODUCT IMAGES
-- ============================================
create table public.product_images (
  id uuid primary key default gen_random_uuid(),
  product_id uuid not null references public.products(id) on delete cascade,
  storage_path text not null,          -- path in Supabase Storage bucket
  alt_text text,
  sort_order int not null default 0
);

-- ============================================
-- REVIEWS
-- ============================================
create table public.reviews (
  id uuid primary key default gen_random_uuid(),
  product_id uuid not null references public.products(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  rating int not null check (rating between 1 and 5),
  title text,
  body text,
  is_verified_purchase boolean not null default false,
  created_at timestamptz not null default now(),
  unique (product_id, user_id)          -- one review per customer per product
);

-- ============================================
-- WISHLISTS
-- ============================================
create table public.wishlists (
  user_id uuid not null references public.profiles(id) on delete cascade,
  product_id uuid not null references public.products(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (user_id, product_id)
);

-- ============================================
-- ORDERS
-- ============================================
create table public.orders (
  id uuid primary key default gen_random_uuid(),
  order_number text not null unique,    -- human-readable, e.g. BG-2026-00042
  user_id uuid not null references public.profiles(id) on delete restrict,
  status order_status not null default 'pending',

  shipping_address jsonb not null,      -- snapshot at time of order, not a live FK
  billing_address jsonb,

  subtotal numeric(10,2) not null,
  shipping_cost numeric(10,2) not null default 0,
  tax numeric(10,2) not null default 0,
  discount numeric(10,2) not null default 0,
  total numeric(10,2) not null,

  promo_code text,
  stripe_payment_intent_id text,
  tracking_number text,
  tracking_carrier text,

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index idx_orders_user on public.orders(user_id);
create index idx_orders_status on public.orders(status);

-- ============================================
-- ORDER ITEMS
-- ============================================
create table public.order_items (
  id uuid primary key default gen_random_uuid(),
  order_id uuid not null references public.orders(id) on delete cascade,
  product_id uuid references public.products(id) on delete set null,

  -- Snapshot fields — survive even if the product is later edited/deleted
  product_name text not null,
  product_sku text,
  unit_price numeric(10,2) not null,
  quantity int not null check (quantity > 0),
  line_total numeric(10,2) not null
);

-- ============================================
-- SUPPORT TICKETS
-- ============================================
create table public.support_tickets (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  order_id uuid references public.orders(id) on delete set null,
  subject text not null,
  status ticket_status not null default 'open',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.support_messages (
  id uuid primary key default gen_random_uuid(),
  ticket_id uuid not null references public.support_tickets(id) on delete cascade,
  sender_id uuid not null references public.profiles(id) on delete cascade,
  body text not null,
  created_at timestamptz not null default now()
);

-- ============================================
-- PROMO CODES & FLASH SALES
-- ============================================
create table public.promo_codes (
  id uuid primary key default gen_random_uuid(),
  code text not null unique,
  discount_type text not null check (discount_type in ('percentage', 'fixed')),
  discount_value numeric(10,2) not null,
  min_order_value numeric(10,2) default 0,
  max_uses int,
  used_count int not null default 0,
  starts_at timestamptz,
  expires_at timestamptz,
  is_active boolean not null default true
);

create table public.flash_sales (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  discount_percentage numeric(5,2) not null,
  starts_at timestamptz not null,
  ends_at timestamptz not null,
  is_active boolean not null default true
);

create table public.flash_sale_products (
  flash_sale_id uuid not null references public.flash_sales(id) on delete cascade,
  product_id uuid not null references public.products(id) on delete cascade,
  primary key (flash_sale_id, product_id)
);

-- ============================================
-- STORE SETTINGS (singleton-style key/value)
-- ============================================
create table public.store_settings (
  key text primary key,
  value jsonb not null,
  updated_at timestamptz not null default now()
);