-- WorkSpace (BU2) product seed
-- Idempotent: skips if any non-deleted category already exists.
-- Run BEFORE the Meilisearch plugin is installed so BulkIndexAsync picks these up.

DO $seed$
DECLARE
    v_cat1  integer;
    v_cat2  integer;
    v_prod  integer;
BEGIN
    IF EXISTS (SELECT 1 FROM "Category" WHERE "Name" = 'Office Chairs' AND "Deleted" = false LIMIT 1) THEN
        RAISE NOTICE 'BU2 already seeded – skipping';
        RETURN;
    END IF;

    -- ── Category: Office Chairs ─────────────────────────────────────────────
    INSERT INTO "Category" (
        "Name","Description","CategoryTemplateId",
        "MetaKeywords","MetaDescription","MetaTitle",
        "ParentCategoryId","PictureId",
        "PageSize","AllowCustomersToSelectPageSize","PageSizeOptions",
        "ShowOnHomepage","SubjectToAcl","LimitedToStores",
        "Published","Deleted","DisplayOrder",
        "CreatedOnUtc","UpdatedOnUtc",
        "PriceRangeFiltering","PriceFrom","PriceTo","ManuallyPriceRange",
        "RestrictFromVendors"
    ) VALUES (
        'Office Chairs','<p>Ergonomic seating engineered for long working sessions.</p>',1,
        NULL,NULL,NULL,
        0,0,
        6,true,'6, 3, 9',
        true,false,false,
        true,false,1,
        NOW(),NOW(),
        false,0,0,false,
        false
    ) RETURNING "Id" INTO v_cat1;

    INSERT INTO "UrlRecord" ("EntityId","EntityName","Slug","IsActive","LanguageId")
    VALUES (v_cat1,'Category','office-chairs',true,0);

    -- ── Category: Desks & Monitors ──────────────────────────────────────────
    INSERT INTO "Category" (
        "Name","Description","CategoryTemplateId",
        "MetaKeywords","MetaDescription","MetaTitle",
        "ParentCategoryId","PictureId",
        "PageSize","AllowCustomersToSelectPageSize","PageSizeOptions",
        "ShowOnHomepage","SubjectToAcl","LimitedToStores",
        "Published","Deleted","DisplayOrder",
        "CreatedOnUtc","UpdatedOnUtc",
        "PriceRangeFiltering","PriceFrom","PriceTo","ManuallyPriceRange",
        "RestrictFromVendors"
    ) VALUES (
        'Desks & Monitors','<p>Height-adjustable desks and professional-grade displays.</p>',1,
        NULL,NULL,NULL,
        0,0,
        6,true,'6, 3, 9',
        false,false,false,
        true,false,2,
        NOW(),NOW(),
        false,0,0,false,
        false
    ) RETURNING "Id" INTO v_cat2;

    INSERT INTO "UrlRecord" ("EntityId","EntityName","Slug","IsActive","LanguageId")
    VALUES (v_cat2,'Category','desks-monitors',true,0);

    -- ── Product 1: Ergonomic Mesh Chair ────────────────────────────────────
    INSERT INTO "Product" (
        "ProductTypeId","ParentGroupedProductId","VisibleIndividually",
        "Name","ShortDescription","FullDescription","AdminComment",
        "ProductTemplateId","VendorId","ShowOnHomepage",
        "MetaKeywords","MetaDescription","MetaTitle",
        "AllowCustomerReviews","ApprovedRatingSum","NotApprovedRatingSum",
        "ApprovedTotalReviews","NotApprovedTotalReviews",
        "SubjectToAcl","LimitedToStores",
        "Sku","ManufacturerPartNumber","Gtin",
        "IsGiftCard","GiftCardTypeId","OverriddenGiftCardAmount",
        "RequireOtherProducts","RequiredProductIds","AutomaticallyAddRequiredProducts",
        "IsDownload","DownloadId","UnlimitedDownloads","MaxNumberOfDownloads",
        "DownloadExpirationDays","DownloadActivationTypeId",
        "HasSampleDownload","SampleDownloadId","HasUserAgreement","UserAgreementText",
        "IsRecurring","RecurringCycleLength","RecurringCyclePeriodId","RecurringTotalCycles",
        "IsRental","RentalPriceLength","RentalPricePeriodId",
        "IsShipEnabled","IsFreeShipping","ShipSeparately","AdditionalShippingCharge",
        "DeliveryDateId","IsTaxExempt","TaxCategoryId",
        "ManageInventoryMethodId","ProductAvailabilityRangeId",
        "UseMultipleWarehouses","WarehouseId","StockQuantity",
        "DisplayStockAvailability","DisplayStockQuantity",
        "MinStockQuantity","LowStockActivityId","NotifyAdminForQuantityBelow",
        "BackorderModeId","AllowBackInStockSubscriptions",
        "OrderMinimumQuantity","OrderMaximumQuantity",
        "AllowedQuantities","AllowAddingOnlyExistingAttributeCombinations",
        "DisplayAttributeCombinationImagesOnly","NotReturnable",
        "DisableBuyButton","DisableWishlistButton",
        "AvailableForPreOrder","PreOrderAvailabilityStartDateTimeUtc",
        "CallForPrice",
        "Price","OldPrice","ProductCost",
        "CustomerEntersPrice","MinimumCustomerEnteredPrice","MaximumCustomerEnteredPrice",
        "BasepriceEnabled","BasepriceAmount","BasepriceUnitId","BasepriceBaseAmount","BasepriceBaseUnitId",
        "MarkAsNew","MarkAsNewStartDateTimeUtc","MarkAsNewEndDateTimeUtc",
        "Weight","Length","Width","Height",
        "AvailableStartDateTimeUtc","AvailableEndDateTimeUtc",
        "DisplayOrder","Published","Deleted",
        "CreatedOnUtc","UpdatedOnUtc",
        "AgeVerification","MinimumAgeToPurchase"
    ) VALUES (
        5,0,true,
        'Ergonomic Mesh Chair','Full-mesh back, 4D armrests, lumbar support.',
        '<p>Breathable mesh back with individually adjustable lumbar support. 4D armrests, seat-depth slider, and 135° recline. Engineered for 8+ hour sessions.</p>',
        NULL,
        1,0,true,
        NULL,NULL,NULL,
        true,0,0,0,0,
        false,false,
        'WS-CHAIR-001',NULL,NULL,
        false,0,NULL,
        false,NULL,false,
        false,0,true,10,
        NULL,0,
        false,0,false,NULL,
        false,100,0,10,
        false,1,0,
        true,false,false,0,
        0,false,0,
        0,0,
        false,0,15,
        false,false,
        0,0,1,
        0,false,
        1,10000,
        NULL,false,
        false,false,
        false,false,
        false,NULL,
        false,
        699.00,899.00,0,
        false,0,1000,
        false,0,0,0,0,
        false,NULL,NULL,
        0,0,0,0,
        NULL,NULL,
        0,true,false,
        NOW(),NOW(),
        false,0
    ) RETURNING "Id" INTO v_prod;

    INSERT INTO "Product_Category_Mapping" ("ProductId","CategoryId","IsFeaturedProduct","DisplayOrder")
    VALUES (v_prod,v_cat1,true,1);
    INSERT INTO "UrlRecord" ("EntityId","EntityName","Slug","IsActive","LanguageId")
    VALUES (v_prod,'Product','ergonomic-mesh-chair',true,0);

    -- ── Product 2: Adjustable Standing Desk ────────────────────────────────
    INSERT INTO "Product" (
        "ProductTypeId","ParentGroupedProductId","VisibleIndividually",
        "Name","ShortDescription","FullDescription","AdminComment",
        "ProductTemplateId","VendorId","ShowOnHomepage",
        "MetaKeywords","MetaDescription","MetaTitle",
        "AllowCustomerReviews","ApprovedRatingSum","NotApprovedRatingSum",
        "ApprovedTotalReviews","NotApprovedTotalReviews",
        "SubjectToAcl","LimitedToStores",
        "Sku","ManufacturerPartNumber","Gtin",
        "IsGiftCard","GiftCardTypeId","OverriddenGiftCardAmount",
        "RequireOtherProducts","RequiredProductIds","AutomaticallyAddRequiredProducts",
        "IsDownload","DownloadId","UnlimitedDownloads","MaxNumberOfDownloads",
        "DownloadExpirationDays","DownloadActivationTypeId",
        "HasSampleDownload","SampleDownloadId","HasUserAgreement","UserAgreementText",
        "IsRecurring","RecurringCycleLength","RecurringCyclePeriodId","RecurringTotalCycles",
        "IsRental","RentalPriceLength","RentalPricePeriodId",
        "IsShipEnabled","IsFreeShipping","ShipSeparately","AdditionalShippingCharge",
        "DeliveryDateId","IsTaxExempt","TaxCategoryId",
        "ManageInventoryMethodId","ProductAvailabilityRangeId",
        "UseMultipleWarehouses","WarehouseId","StockQuantity",
        "DisplayStockAvailability","DisplayStockQuantity",
        "MinStockQuantity","LowStockActivityId","NotifyAdminForQuantityBelow",
        "BackorderModeId","AllowBackInStockSubscriptions",
        "OrderMinimumQuantity","OrderMaximumQuantity",
        "AllowedQuantities","AllowAddingOnlyExistingAttributeCombinations",
        "DisplayAttributeCombinationImagesOnly","NotReturnable",
        "DisableBuyButton","DisableWishlistButton",
        "AvailableForPreOrder","PreOrderAvailabilityStartDateTimeUtc",
        "CallForPrice",
        "Price","OldPrice","ProductCost",
        "CustomerEntersPrice","MinimumCustomerEnteredPrice","MaximumCustomerEnteredPrice",
        "BasepriceEnabled","BasepriceAmount","BasepriceUnitId","BasepriceBaseAmount","BasepriceBaseUnitId",
        "MarkAsNew","MarkAsNewStartDateTimeUtc","MarkAsNewEndDateTimeUtc",
        "Weight","Length","Width","Height",
        "AvailableStartDateTimeUtc","AvailableEndDateTimeUtc",
        "DisplayOrder","Published","Deleted",
        "CreatedOnUtc","UpdatedOnUtc",
        "AgeVerification","MinimumAgeToPurchase"
    ) VALUES (
        5,0,true,
        'Adjustable Standing Desk','Electric sit-stand, 140 × 70 cm bamboo top.',
        '<p>Dual-motor electric height adjustment (62–128 cm). Bamboo surface with integrated cable tray and 3-memory preset controller. Holds up to 80 kg.</p>',
        NULL,
        1,0,true,
        NULL,NULL,NULL,
        true,0,0,0,0,
        false,false,
        'WS-DESK-001',NULL,NULL,
        false,0,NULL,
        false,NULL,false,
        false,0,true,10,
        NULL,0,
        false,0,false,NULL,
        false,100,0,10,
        false,1,0,
        true,false,false,0,
        0,false,0,
        0,0,
        false,0,8,
        false,false,
        0,0,1,
        0,false,
        1,10000,
        NULL,false,
        false,false,
        false,false,
        false,NULL,
        false,
        849.00,0,0,
        false,0,1000,
        false,0,0,0,0,
        true,NULL,NULL,
        0,0,0,0,
        NULL,NULL,
        0,true,false,
        NOW(),NOW(),
        false,0
    ) RETURNING "Id" INTO v_prod;

    INSERT INTO "Product_Category_Mapping" ("ProductId","CategoryId","IsFeaturedProduct","DisplayOrder")
    VALUES (v_prod,v_cat2,true,1);
    INSERT INTO "UrlRecord" ("EntityId","EntityName","Slug","IsActive","LanguageId")
    VALUES (v_prod,'Product','adjustable-standing-desk',true,0);

    -- ── Product 3: 27" Ultrawide Monitor ───────────────────────────────────
    INSERT INTO "Product" (
        "ProductTypeId","ParentGroupedProductId","VisibleIndividually",
        "Name","ShortDescription","FullDescription","AdminComment",
        "ProductTemplateId","VendorId","ShowOnHomepage",
        "MetaKeywords","MetaDescription","MetaTitle",
        "AllowCustomerReviews","ApprovedRatingSum","NotApprovedRatingSum",
        "ApprovedTotalReviews","NotApprovedTotalReviews",
        "SubjectToAcl","LimitedToStores",
        "Sku","ManufacturerPartNumber","Gtin",
        "IsGiftCard","GiftCardTypeId","OverriddenGiftCardAmount",
        "RequireOtherProducts","RequiredProductIds","AutomaticallyAddRequiredProducts",
        "IsDownload","DownloadId","UnlimitedDownloads","MaxNumberOfDownloads",
        "DownloadExpirationDays","DownloadActivationTypeId",
        "HasSampleDownload","SampleDownloadId","HasUserAgreement","UserAgreementText",
        "IsRecurring","RecurringCycleLength","RecurringCyclePeriodId","RecurringTotalCycles",
        "IsRental","RentalPriceLength","RentalPricePeriodId",
        "IsShipEnabled","IsFreeShipping","ShipSeparately","AdditionalShippingCharge",
        "DeliveryDateId","IsTaxExempt","TaxCategoryId",
        "ManageInventoryMethodId","ProductAvailabilityRangeId",
        "UseMultipleWarehouses","WarehouseId","StockQuantity",
        "DisplayStockAvailability","DisplayStockQuantity",
        "MinStockQuantity","LowStockActivityId","NotifyAdminForQuantityBelow",
        "BackorderModeId","AllowBackInStockSubscriptions",
        "OrderMinimumQuantity","OrderMaximumQuantity",
        "AllowedQuantities","AllowAddingOnlyExistingAttributeCombinations",
        "DisplayAttributeCombinationImagesOnly","NotReturnable",
        "DisableBuyButton","DisableWishlistButton",
        "AvailableForPreOrder","PreOrderAvailabilityStartDateTimeUtc",
        "CallForPrice",
        "Price","OldPrice","ProductCost",
        "CustomerEntersPrice","MinimumCustomerEnteredPrice","MaximumCustomerEnteredPrice",
        "BasepriceEnabled","BasepriceAmount","BasepriceUnitId","BasepriceBaseAmount","BasepriceBaseUnitId",
        "MarkAsNew","MarkAsNewStartDateTimeUtc","MarkAsNewEndDateTimeUtc",
        "Weight","Length","Width","Height",
        "AvailableStartDateTimeUtc","AvailableEndDateTimeUtc",
        "DisplayOrder","Published","Deleted",
        "CreatedOnUtc","UpdatedOnUtc",
        "AgeVerification","MinimumAgeToPurchase"
    ) VALUES (
        5,0,true,
        '27" Ultrawide Monitor','QHD IPS panel, 144 Hz, USB-C 90W PD.',
        '<p>27-inch 2560×1440 IPS display with 144 Hz refresh, 1 ms GtG, USB-C 90W power delivery, and factory-calibrated colour accuracy (Delta E &lt; 2). Height and tilt adjustable stand included.</p>',
        NULL,
        1,0,false,
        NULL,NULL,NULL,
        true,0,0,0,0,
        false,false,
        'WS-MON-001',NULL,NULL,
        false,0,NULL,
        false,NULL,false,
        false,0,true,10,
        NULL,0,
        false,0,false,NULL,
        false,100,0,10,
        false,1,0,
        true,false,false,0,
        0,false,0,
        0,0,
        false,0,20,
        false,false,
        0,0,1,
        0,false,
        1,10000,
        NULL,false,
        false,false,
        false,false,
        false,NULL,
        false,
        549.00,649.00,0,
        false,0,1000,
        false,0,0,0,0,
        false,NULL,NULL,
        0,0,0,0,
        NULL,NULL,
        1,true,false,
        NOW(),NOW(),
        false,0
    ) RETURNING "Id" INTO v_prod;

    INSERT INTO "Product_Category_Mapping" ("ProductId","CategoryId","IsFeaturedProduct","DisplayOrder")
    VALUES (v_prod,v_cat2,false,2);
    INSERT INTO "UrlRecord" ("EntityId","EntityName","Slug","IsActive","LanguageId")
    VALUES (v_prod,'Product','27-ultrawide-monitor',true,0);

    -- ── Product 4: Cable Management Kit ────────────────────────────────────
    INSERT INTO "Product" (
        "ProductTypeId","ParentGroupedProductId","VisibleIndividually",
        "Name","ShortDescription","FullDescription","AdminComment",
        "ProductTemplateId","VendorId","ShowOnHomepage",
        "MetaKeywords","MetaDescription","MetaTitle",
        "AllowCustomerReviews","ApprovedRatingSum","NotApprovedRatingSum",
        "ApprovedTotalReviews","NotApprovedTotalReviews",
        "SubjectToAcl","LimitedToStores",
        "Sku","ManufacturerPartNumber","Gtin",
        "IsGiftCard","GiftCardTypeId","OverriddenGiftCardAmount",
        "RequireOtherProducts","RequiredProductIds","AutomaticallyAddRequiredProducts",
        "IsDownload","DownloadId","UnlimitedDownloads","MaxNumberOfDownloads",
        "DownloadExpirationDays","DownloadActivationTypeId",
        "HasSampleDownload","SampleDownloadId","HasUserAgreement","UserAgreementText",
        "IsRecurring","RecurringCycleLength","RecurringCyclePeriodId","RecurringTotalCycles",
        "IsRental","RentalPriceLength","RentalPricePeriodId",
        "IsShipEnabled","IsFreeShipping","ShipSeparately","AdditionalShippingCharge",
        "DeliveryDateId","IsTaxExempt","TaxCategoryId",
        "ManageInventoryMethodId","ProductAvailabilityRangeId",
        "UseMultipleWarehouses","WarehouseId","StockQuantity",
        "DisplayStockAvailability","DisplayStockQuantity",
        "MinStockQuantity","LowStockActivityId","NotifyAdminForQuantityBelow",
        "BackorderModeId","AllowBackInStockSubscriptions",
        "OrderMinimumQuantity","OrderMaximumQuantity",
        "AllowedQuantities","AllowAddingOnlyExistingAttributeCombinations",
        "DisplayAttributeCombinationImagesOnly","NotReturnable",
        "DisableBuyButton","DisableWishlistButton",
        "AvailableForPreOrder","PreOrderAvailabilityStartDateTimeUtc",
        "CallForPrice",
        "Price","OldPrice","ProductCost",
        "CustomerEntersPrice","MinimumCustomerEnteredPrice","MaximumCustomerEnteredPrice",
        "BasepriceEnabled","BasepriceAmount","BasepriceUnitId","BasepriceBaseAmount","BasepriceBaseUnitId",
        "MarkAsNew","MarkAsNewStartDateTimeUtc","MarkAsNewEndDateTimeUtc",
        "Weight","Length","Width","Height",
        "AvailableStartDateTimeUtc","AvailableEndDateTimeUtc",
        "DisplayOrder","Published","Deleted",
        "CreatedOnUtc","UpdatedOnUtc",
        "AgeVerification","MinimumAgeToPurchase"
    ) VALUES (
        5,0,true,
        'Cable Management Kit','Under-desk tray, 10 velcro ties, 3 cable clips.',
        '<p>Complete desk tidy kit: aluminium under-desk cable tray (60 cm), 10 reusable velcro ties, 3 adhesive cable clips, and a power strip holder. Compatible with all WorkSpace desks.</p>',
        NULL,
        1,0,false,
        NULL,NULL,NULL,
        true,0,0,0,0,
        false,false,
        'WS-ACC-001',NULL,NULL,
        false,0,NULL,
        false,NULL,false,
        false,0,true,10,
        NULL,0,
        false,0,false,NULL,
        false,100,0,10,
        false,1,0,
        true,false,false,0,
        0,false,0,
        0,0,
        false,0,100,
        false,false,
        0,0,1,
        0,false,
        1,10000,
        NULL,false,
        false,false,
        false,false,
        false,NULL,
        false,
        39.00,0,0,
        false,0,1000,
        false,0,0,0,0,
        true,NULL,NULL,
        0,0,0,0,
        NULL,NULL,
        1,true,false,
        NOW(),NOW(),
        false,0
    ) RETURNING "Id" INTO v_prod;

    INSERT INTO "Product_Category_Mapping" ("ProductId","CategoryId","IsFeaturedProduct","DisplayOrder")
    VALUES (v_prod,v_cat2,false,3);
    INSERT INTO "UrlRecord" ("EntityId","EntityName","Slug","IsActive","LanguageId")
    VALUES (v_prod,'Product','cable-management-kit',true,0);

    RAISE NOTICE 'WorkSpace (BU2) seed complete: 2 categories, 4 products';
END $seed$;
