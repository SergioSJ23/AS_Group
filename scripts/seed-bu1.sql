-- HomeStyle (BU1) product seed
-- Idempotent: skips if any non-deleted category already exists.
-- Run BEFORE the Meilisearch plugin is installed so BulkIndexAsync picks these up.

DO $seed$
DECLARE
    v_cat1  integer;
    v_cat2  integer;
    v_cat3  integer;
    v_cat4  integer;
    v_prod  integer;
BEGIN
    IF EXISTS (SELECT 1 FROM "Category" WHERE "Name" = 'Sofas' AND "Deleted" = false LIMIT 1) THEN
        RAISE NOTICE 'BU1 already seeded – skipping';
        RETURN;
    END IF;

    -- ── Category: Sofas ─────────────────────────────────────────────────────
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
        'Sofas','<p>Handcrafted sofas for a warm, inviting home.</p>',1,
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
    VALUES (v_cat1,'Category','sofas',true,0);

    -- ── Category: Tables ────────────────────────────────────────────────────
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
        'Tables','<p>Solid wood tables crafted to last a lifetime.</p>',1,
        NULL,NULL,NULL,
        0,0,
        6,true,'6, 3, 9',
        true,false,false,
        true,false,2,
        NOW(),NOW(),
        false,0,0,false,
        false
    ) RETURNING "Id" INTO v_cat2;
    INSERT INTO "UrlRecord" ("EntityId","EntityName","Slug","IsActive","LanguageId")
    VALUES (v_cat2,'Category','tables',true,0);

    -- ── Category: Pendant Lights ────────────────────────────────────────────
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
        'Pendant Lights','<p>Statement pendant lights for every room.</p>',1,
        NULL,NULL,NULL,
        0,0,
        6,true,'6, 3, 9',
        true,false,false,
        true,false,3,
        NOW(),NOW(),
        false,0,0,false,
        false
    ) RETURNING "Id" INTO v_cat3;
    INSERT INTO "UrlRecord" ("EntityId","EntityName","Slug","IsActive","LanguageId")
    VALUES (v_cat3,'Category','pendant-lights',true,0);

    -- ── Category: Table Lamps ───────────────────────────────────────────────
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
        'Table Lamps','<p>Elegant table lamps to set the mood.</p>',1,
        NULL,NULL,NULL,
        0,0,
        6,true,'6, 3, 9',
        true,false,false,
        true,false,4,
        NOW(),NOW(),
        false,0,0,false,
        false
    ) RETURNING "Id" INTO v_cat4;
    INSERT INTO "UrlRecord" ("EntityId","EntityName","Slug","IsActive","LanguageId")
    VALUES (v_cat4,'Category','table-lamps',true,0);

    -- ── Product 1: Linen Sofa ───────────────────────────────────────────────
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
        'Linen Sofa','Handcrafted 3-seater sofa with solid oak legs.',
        '<p>Natural linen fabric on a solid oak frame. Timeless design for any living space. Available in natural, sage and charcoal.</p>',
        NULL,
        1,0,true,
        NULL,NULL,NULL,
        true,0,0,0,0,
        false,false,
        'HS-SOFA-001',NULL,NULL,
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
        false,0,30,
        false,false,
        0,0,1,
        0,false,
        1,10000,
        NULL,false,
        false,false,
        false,false,
        false,NULL,
        false,
        1249.00,1499.00,0,
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
    VALUES (v_prod,'Product','linen-sofa',true,0);

    -- ── Product 2: Walnut Coffee Table ──────────────────────────────────────
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
        'Walnut Coffee Table','Solid walnut top, 120 × 60 cm.',
        '<p>Hand-oiled solid walnut with hairpin steel legs. Pairs beautifully with the Linen Sofa.</p>',
        NULL,
        1,0,true,
        NULL,NULL,NULL,
        true,0,0,0,0,
        false,false,
        'HS-TABLE-001',NULL,NULL,
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
        449.00,0,0,
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
    VALUES (v_prod,v_cat2,true,1);
    INSERT INTO "UrlRecord" ("EntityId","EntityName","Slug","IsActive","LanguageId")
    VALUES (v_prod,'Product','walnut-coffee-table',true,0);

    -- ── Product 3: Rattan Pendant Light ────────────────────────────────────
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
        'Rattan Pendant Light','Handwoven rattan lamp, 40 cm diameter.',
        '<p>Natural rattan weave with a warm Edison-style bulb socket. Creates beautiful dappled light patterns.</p>',
        NULL,
        1,0,true,
        NULL,NULL,NULL,
        true,0,0,0,0,
        false,false,
        'HS-LIGHT-001',NULL,NULL,
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
        false,0,40,
        false,false,
        0,0,1,
        0,false,
        1,10000,
        NULL,false,
        false,false,
        false,false,
        false,NULL,
        false,
        129.00,0,0,
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
    VALUES (v_prod,v_cat3,true,1);
    INSERT INTO "UrlRecord" ("EntityId","EntityName","Slug","IsActive","LanguageId")
    VALUES (v_prod,'Product','rattan-pendant-light',true,0);

    -- ── Product 4: Marble Table Lamp ────────────────────────────────────────
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
        'Marble Table Lamp','White Carrara marble base with a linen shade.',
        '<p>Elegant Carrara marble base paired with a hand-stitched natural linen shade. E27 socket, 40 W max.</p>',
        NULL,
        1,0,true,
        NULL,NULL,NULL,
        true,0,0,0,0,
        false,false,
        'HS-LIGHT-002',NULL,NULL,
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
        false,0,25,
        false,false,
        0,0,1,
        0,false,
        1,10000,
        NULL,false,
        false,false,
        false,false,
        false,NULL,
        false,
        189.00,0,0,
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
    VALUES (v_prod,v_cat4,true,1);
    INSERT INTO "UrlRecord" ("EntityId","EntityName","Slug","IsActive","LanguageId")
    VALUES (v_prod,'Product','marble-table-lamp',true,0);

    RAISE NOTICE 'HomeStyle (BU1) seed complete: 4 categories, 4 products';
END $seed$;
