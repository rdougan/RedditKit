// RDKClient+Requests.m
//
// Copyright (c) 2013 Sam Symons (http://samsymons.com/)
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in
// all copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
// THE SOFTWARE.

#import "RDKClient+Requests.h"
#import "RDKClient+Errors.h"
#import "RDKOAuthClient.h"
#import "RDKPagination.h"
#import "RDKObjectBuilder.h"

@implementation RDKClient (Requests)

- (NSURLSessionDataTask *)basicPostTaskWithPath:(NSString *)path parameters:(NSDictionary *)parameters completion:(RDKCompletionBlock)completion
{
    NSParameterAssert(path);
    
    if (![self isSignedIn])
    {
        if (completion)
        {
            completion([RDKClient authenticationRequiredError]);
        }
        
        return nil;
    }
    
    return [self postPath:path parameters:parameters completion:^(NSHTTPURLResponse *response, id responseObject, NSError *error) {
        if (completion)
        {
            completion(error);
        }
    }];
}

- (NSURLSessionDataTask *)listingTaskWithPath:(NSString *)path parameters:(NSDictionary *)parameters pagination:(RDKPagination *)pagination completion:(RDKListingCompletionBlock)completion
{
    NSParameterAssert(path);
    
    NSMutableDictionary *taskParameters = [NSMutableDictionary dictionary];
    [taskParameters addEntriesFromDictionary:parameters];
    [taskParameters addEntriesFromDictionary:[pagination dictionaryValue]];
    
    return [self getPath:path parameters:taskParameters completion:^(NSHTTPURLResponse *response, id responseObject, NSError *error) {
        if (!completion)
        {
            return;
        }
        
        if (responseObject)
        {
            dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
                NSDictionary *response = responseObject;
                if ([responseObject isKindOfClass:[NSArray class]])
                {
                    response = [responseObject lastObject];
                }
                
                NSArray *links = [self objectsFromListingResponse:response];
                RDKPagination *pagination = [RDKPagination paginationFromListingResponse:response];
                
                dispatch_async(dispatch_get_main_queue(), ^{
                    completion(links, pagination, nil);
                });
            });
        }
        else
        {
            completion(nil, nil, error);
        }
    }];
}

- (NSURLSessionDataTask *)friendTaskWithContainer:(NSString *)container subredditName:(NSString *)subredditName name:(NSString *)name type:(NSString *)type completion:(RDKCompletionBlock)completion
{
    NSParameterAssert(container);
    NSParameterAssert(name);
    NSParameterAssert(type);
    
    NSDictionary *parameters = @{@"container": container, @"name": name, @"type": type};
    
    if (subredditName)
    {
        NSMutableDictionary *mutableParameters = [parameters mutableCopy];
        mutableParameters[@"r"] = subredditName;
        parameters = [mutableParameters copy];
    }
    
    return [self basicPostTaskWithPath:@"api/friend" parameters:parameters completion:completion];
}

- (NSURLSessionDataTask *)unfriendTaskWithContainer:(NSString *)container subredditName:(NSString *)subredditName name:(NSString *)name type:(NSString *)type completion:(RDKCompletionBlock)completion
{
    NSParameterAssert(container);
    NSParameterAssert(name);
    NSParameterAssert(type);
    
    NSDictionary *parameters = @{@"container": container, @"name": name, @"type": type};
    
    if (subredditName)
    {
        NSMutableDictionary *mutableParameters = [parameters mutableCopy];
        mutableParameters[@"r"] = subredditName;
        parameters = [mutableParameters copy];
    }
    
    return [self basicPostTaskWithPath:@"api/unfriend" parameters:parameters completion:completion];
}

#pragma mark - Response Helpers

- (NSArray *)objectsFromListingResponse:(NSDictionary *)listingResponse
{
    NSParameterAssert(listingResponse);
    
    NSString *kind = listingResponse[@"kind"];
    if (![kind isEqualToString:@"Listing"])
    {
        return nil;
    }
    
    NSArray *objectsAsJSON = listingResponse[@"data"][@"children"];
    NSMutableArray *objects = [[NSMutableArray alloc] initWithCapacity:[objectsAsJSON count]];
    
    for (NSDictionary *objectJSON in objectsAsJSON)
    {
        id object = [RDKObjectBuilder objectFromJSON:objectJSON];
        
        if (object)
        {
            [objects addObject:object];
        }
    }
    
    return [objects copy];
}

#pragma mark - Request Helpers

- (NSURLSessionDataTask *)getPath:(NSString *)path parameters:(NSDictionary *)parameters completion:(RDKRequestCompletionBlock)completion
{
    return [self taskWithMethod:@"GET" path:path parameters:parameters completion:completion];
}

- (NSURLSessionDataTask *)postPath:(NSString *)path parameters:(NSDictionary *)parameters completion:(RDKRequestCompletionBlock)completion
{
    return [self taskWithMethod:@"POST" path:path parameters:parameters completion:completion];
}

- (NSURLSessionDataTask *)putPath:(NSString *)path parameters:(NSDictionary *)parameters completion:(RDKRequestCompletionBlock)completion
{
    return [self taskWithMethod:@"PUT" path:path parameters:parameters completion:completion];
}

- (NSURLSessionDataTask *)deletePath:(NSString *)path parameters:(NSDictionary *)parameters completion:(RDKRequestCompletionBlock)completion
{
    return [self taskWithMethod:@"DELETE" path:path parameters:parameters completion:completion];
}

- (NSURLSessionDataTask *)taskWithMethod:(NSString *)method path:(NSString *)path parameters:(NSDictionary *)parameters completion:(RDKRequestCompletionBlock)completion
{
    NSParameterAssert(method);
    NSParameterAssert(path);
    
    NSMutableDictionary *alteredParameters = [parameters mutableCopy];
    [alteredParameters setObject:@"json" forKey:@"api_type"];
    
    NSURL *baseURL = [[self class] APIBaseURL];
    
    if ([self isKindOfClass:[RDKOAuthClient class]] && [self isSignedIn])
    {
        baseURL = [[self class] APIBaseHTTPSURL];
    }
    
    NSLog(@"Building request with base URL: %@", baseURL);
    
    NSString *URLString = [[NSURL URLWithString:path relativeToURL:baseURL] absoluteString];
    NSError *serializationError = nil;
    NSURLRequest *request = [[self requestSerializer] requestWithMethod:method URLString:URLString parameters:[alteredParameters copy] error:&serializationError];
    
    if (serializationError)
    {
        if (completion)
        {
            completion(nil, nil, serializationError);
        }
        
        return nil;
    }
    
    NSURLSessionDataTask *task = [self dataTaskWithRequest:request completionHandler:^(NSURLResponse *response, id responseObject, NSError *error) {
        if (completion)
        {
            completion((NSHTTPURLResponse *)response, responseObject, error);
        }
    }];
    
    [task resume];
    
    return task;
}

@end
