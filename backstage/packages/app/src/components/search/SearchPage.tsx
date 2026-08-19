import React from 'react';
import { Grid, Paper } from '@material-ui/core';
import { SearchType } from '@backstage/plugin-search';
import { SearchBar, SearchResult } from '@backstage/plugin-search-react';
import {
  CatalogSearchResultListItem,
} from '@backstage/plugin-catalog';
import { Content, Header, Page } from '@backstage/core-components';

export const searchPage = (
  <Page themeId="home">
    <Header title="Search" />
    <Content>
      <Grid container direction="row">
        <Grid item xs={12}>
          <Paper>
            <SearchBar />
          </Paper>
        </Grid>
        <Grid item xs={3}>
          <SearchType.Accordion
            name="Result Type"
            defaultValue="software-catalog"
            types={[{ value: 'software-catalog', name: 'Software Catalog', icon: <></> }]}
          />
        </Grid>
        <Grid item xs={9}>
          <SearchResult>
            <CatalogSearchResultListItem />
          </SearchResult>
        </Grid>
      </Grid>
    </Content>
  </Page>
);
