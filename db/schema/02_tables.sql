-- FOOD-101. Таблицы FoodExpress

CREATE TABLE rigun_food.client (
    client_id uuid PRIMARY KEY DEFAULT exts.uuid_generate_v4(),
    login varchar(100) NOT NULL UNIQUE,
    password varchar(32) NOT NULL,
    phone_number char(12) NOT NULL UNIQUE,
    CONSTRAINT client_password_length CHECK (length(password) = 32)
);

CREATE TABLE rigun_food.address (
    address_id uuid PRIMARY KEY DEFAULT exts.uuid_generate_v4(),
    street varchar(150) NOT NULL,
    house_number varchar(20) NOT NULL,
    apartment_office varchar(30)
);

CREATE TABLE rigun_food.client_address (
    client_id uuid NOT NULL REFERENCES rigun_food.client(client_id),
    address_id uuid NOT NULL REFERENCES rigun_food.address(address_id),
    PRIMARY KEY (client_id, address_id)
);

CREATE TABLE rigun_food.restaurant (
    restaurant_id uuid PRIMARY KEY DEFAULT exts.uuid_generate_v4(),
    restaurant_name varchar(150) NOT NULL,
    address_id uuid NOT NULL UNIQUE REFERENCES rigun_food.address(address_id),
    description text NOT NULL,
    work_start time NOT NULL,
    work_end time NOT NULL,
    company_details text NOT NULL,
    rating numeric(4,2),
    status rigun_food.restaurant_status NOT NULL,
    CONSTRAINT restaurant_work_time CHECK (work_end > work_start),
    CONSTRAINT restaurant_rating_range CHECK (rating BETWEEN 0 AND 5)
);

CREATE TABLE rigun_food.courier (
    courier_id uuid PRIMARY KEY DEFAULT exts.uuid_generate_v4(),
    fio varchar(200) NOT NULL,
    phone_number char(12) NOT NULL UNIQUE,
    status rigun_food.courier_status NOT NULL,
    hire_date date NOT NULL,
    dismissal_date date,
    coefficient numeric(3,2) NOT NULL DEFAULT 0.1,
    CONSTRAINT courier_coefficient_range CHECK (coefficient BETWEEN 0.1 AND 0.5),
    CONSTRAINT courier_dismissal_date CHECK (
        dismissal_date IS NULL OR dismissal_date >= hire_date
    ),
    CONSTRAINT courier_dismissed_status CHECK (
        (status = 'уволен') = (dismissal_date IS NOT NULL)
    )
);

CREATE TABLE rigun_food.courier_pay (
    year integer NOT NULL,
    month integer NOT NULL,
    courier_id uuid NOT NULL REFERENCES rigun_food.courier(courier_id),
    amount numeric(14,2) NOT NULL,
    coefficient_used numeric(3,2) NOT NULL,
    PRIMARY KEY (year, month, courier_id),
    CONSTRAINT courier_pay_month CHECK (month BETWEEN 1 AND 12),
    CONSTRAINT courier_pay_amount CHECK (amount >= 0),
    CONSTRAINT courier_pay_coefficient CHECK (coefficient_used BETWEEN 0.1 AND 0.5)
);

CREATE TABLE rigun_food.product_category (
    product_category_id uuid PRIMARY KEY DEFAULT exts.uuid_generate_v4(),
    product_category_name varchar(150) NOT NULL UNIQUE
);

CREATE TABLE rigun_food.product (
    product_id uuid PRIMARY KEY DEFAULT exts.uuid_generate_v4(),
    product_name varchar(150) NOT NULL,
    product_category_id uuid NOT NULL
        REFERENCES rigun_food.product_category(product_category_id),
    price numeric(12,2) NOT NULL,
    restaurant_id uuid NOT NULL
        REFERENCES rigun_food.restaurant(restaurant_id),
    photo_url text,
    rating numeric(4,2),
    status rigun_food.product_status NOT NULL,
    description text NOT NULL,
    CONSTRAINT product_price_nonnegative CHECK (price >= 0),
    CONSTRAINT product_rating_range CHECK (rating BETWEEN 0 AND 5)
);

CREATE TABLE rigun_food."order" (
    order_id uuid PRIMARY KEY DEFAULT exts.uuid_generate_v4(),
    courier_id uuid NOT NULL REFERENCES rigun_food.courier(courier_id),
    client_id uuid NOT NULL REFERENCES rigun_food.client(client_id),
    address_id uuid NOT NULL REFERENCES rigun_food.address(address_id),
    restaurant_id uuid NOT NULL REFERENCES rigun_food.restaurant(restaurant_id),
    order_timestamp timestamp NOT NULL,
    delivery_timestamp timestamp,
    order_amount numeric(14,2) NOT NULL,
    commission numeric(14,2) NOT NULL,
    total_amount numeric(14,2) NOT NULL,
    status rigun_food.order_status NOT NULL,
    pay_status rigun_food.order_payment_status NOT NULL,
    description text NOT NULL,
    CONSTRAINT order_client_address_fk FOREIGN KEY (client_id, address_id)
        REFERENCES rigun_food.client_address(client_id, address_id),
    CONSTRAINT order_amount_nonnegative CHECK (order_amount >= 0),
    CONSTRAINT order_commission_10_percent CHECK (
        commission = round(order_amount * 0.10, 2)
    ),
    CONSTRAINT order_total_amount CHECK (
        total_amount = order_amount + commission AND total_amount >= 1000
    ),
    CONSTRAINT order_delivery_time CHECK (
        delivery_timestamp IS NULL
        OR delivery_timestamp >= order_timestamp
    ),
    CONSTRAINT order_delivered_timestamp CHECK (
        (status = 'доставлен') = (delivery_timestamp IS NOT NULL)
    )
);

CREATE TABLE rigun_food.payment (
    payment_id uuid PRIMARY KEY DEFAULT exts.uuid_generate_v4(),
    order_id uuid NOT NULL REFERENCES rigun_food."order"(order_id),
    payment_type rigun_food.payment_type NOT NULL,
    amount numeric(14,2) NOT NULL,
    transaction_id varchar(150) NOT NULL UNIQUE,
    transaction_timestamp timestamp NOT NULL,
    status rigun_food.payment_status NOT NULL,
    CONSTRAINT payment_amount_positive CHECK (amount > 0)
);

CREATE UNIQUE INDEX one_successful_payment_per_order
ON rigun_food.payment(order_id)
WHERE status = 'успех';

CREATE TABLE rigun_food.order_structure (
    order_id uuid NOT NULL REFERENCES rigun_food."order"(order_id),
    product_id uuid NOT NULL REFERENCES rigun_food.product(product_id),
    quantity numeric(12,3) NOT NULL,
    PRIMARY KEY (order_id, product_id),
    CONSTRAINT order_structure_quantity CHECK (quantity > 0)
);

CREATE TABLE rigun_food.review (
    review_id uuid PRIMARY KEY DEFAULT exts.uuid_generate_v4(),
    client_id uuid NOT NULL REFERENCES rigun_food.client(client_id),
    review_timestamp timestamp NOT NULL,
    entity_id uuid NOT NULL,
    entity_type rigun_food.review_entity_type NOT NULL,
    order_id uuid NOT NULL REFERENCES rigun_food."order"(order_id),
    description text NOT NULL,
    photo_url text,
    rating numeric(3,1) NOT NULL,
    CONSTRAINT review_rating_range CHECK (rating BETWEEN 1 AND 5),
    CONSTRAINT review_one_per_entity UNIQUE (order_id, entity_type, entity_id)
);
